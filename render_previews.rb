module Artworks
  class RenderPreviews
    attr_reader :artwork, :model_order_count, :mockup_order_count, :responses

    def initialize(artwork)
      @artwork            = artwork
      @mockup_order_count = 0
      @model_order_count  = 0
    end

    def call
      destroy_previews!
      trigger_photoshop_jobs!
      add_product_details_photo!
      add_sizing_photo!
    end

    def job_statuses
      job_ids.map { |id| Photoshop::Status::Check.new(id).call }
    end

    private

    def job_ids
      responses.map { |r| r.dig('_links', 'self', 'href')&.split('/')&.last }
    end

    def destroy_previews!
      artwork.previews.destroy_all
    end

    def trigger_photoshop_jobs!
      @responses = []
      artwork.templates.reload
      # Render standard templates
      @responses << artwork.templates
                           .where(with_model: false, is_standard: true, for_marketing: false)
                           .order(order: :asc)
                           .map { |template| replace_smart_object(template) }

      # Render non-model mockups
      @responses << artwork.templates
                           .where(with_model: false, is_standard: false, for_marketing: false)
                           .map { |template| replace_smart_object(template) }

      @model_order_count = mockup_order_count
      # Render model mockups
      @responses << artwork.templates
                           .where(with_model: true, is_standard: false, for_marketing: false)
                           .map { |template| replace_smart_object(template) }
      # Render marketing mockups
      @responses << artwork.templates
                           .where(for_marketing: true)
                           .map { |template| replace_smart_object(template) }

      @responses.flatten!
      @responses
    end

    def replace_smart_object(template)
      Photoshop::SmartObject::Replace.new(
        {
          artwork_id:    artwork.id,
          template_id:   template.id,
          artwork_input: artwork_input,
          template:      template.file_url,
          log_action:    'photoshop.render_previews',
          url_params:    {
            attachable_type: artwork.class.name,
            attachable_id:   artwork.id,
            upload_type:     'preview',
            order:           template.with_model? ? @model_order_count += 1 : @mockup_order_count += 1,
            for_marketing:   template.for_marketing? ? 'true' : 'false'
          },
          width:         3000
        }
      ).call
    end

    def artwork_input
      size = Manufacturer::Templates.new(artwork.template_type).call.first.first
      upload = artwork.manufacturer_renders.find_by("params->>'size' = ?", size)
      upload.file_url
    end

    def add_product_details_photo!
      url    = 'https://cc-templates.s3.us-west-1.amazonaws.com/product_details.jpg'
      params = { dont_upload_to_dropbox: true, order: 8 }
      Manufacturer::Uploads::UploadFileFromUrl.new(url, artwork, 'preview', nil, params).call
    end

    def add_sizing_photo!
      url    = Artworks::SizingPhotoUrl.new.call(artwork.template_type)
      params = { dont_upload_to_dropbox: true, order: 7 }
      Manufacturer::Uploads::UploadFileFromUrl.new(url, artwork, 'preview', nil, params).call
    end
  end
end
