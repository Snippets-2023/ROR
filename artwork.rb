# == Schema Information
#
# Table name: artworks
#
#  id                              :bigint           not null, primary key
#  artwork_type                    :integer          default("Canvas Wall Art")
#  collection                      :string
#  description                     :text
#  for_rendering_test_process_flag :boolean          default(FALSE), not null
#  intellectual_property_agreement :boolean          default(FALSE)
#  name                            :string
#  processing_submission_flow      :boolean          default(FALSE), not null
#  product_type                    :string
#  reject_reason                   :string
#  retries                         :integer          default(0), not null
#  status                          :integer          default("draft"), not null
#  status_changed_at               :datetime
#  status_on_store                 :integer          default("not_available"), not null
#  store_product_handle            :string
#  submission_status               :integer          default("pending"), not null
#  submission_status_changed_at    :datetime
#  tags                            :string
#  template_type                   :integer
#  user_ip_address                 :inet
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  store_product_id                :bigint
#  user_id                         :bigint           not null
#
# Indexes
#
#  index_artworks_on_user_id  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Artwork < ApplicationRecord
  audited
  include HasFile

  paginates_per 25
  max_paginates_per 100

  COLLECTIONS = [
    'Abstract',
    'Anime',
    'Apparel',
    'Cities',
    'Entrepreneurial',
    'Food & Beverage',
    'Home & Family',
    'Kids',
    'Luxury',
    'Military',
    'Money',
    'Motivational',
    'Movies',
    'Music',
    'Nature & Wildlife',
    'Pop Culture',
    'Science Fiction',
    'Space',
    'Spiritual',
    'Sports',
    'Typography',
    'Vehicles',
    'Video Games'
  ].freeze

  enum artwork_type: {
    'Canvas Wall Art' => 0
  }

  enum template_type: { vertical: 0, horizontal: 1, tall: 2, square: 3, wide: 4 }

  enum status: {
    draft:    0,
    review:   1,
    approved: 2,
    rejected: 3,
    pending_form_submission: 4
  }

  enum status_on_store: {
    not_available: 0,
    draft:         1,
    archived:      2,
    published:     3,
    deleted:       4
  }, _prefix: true

  enum submission_status: {
    pending:                    0,
    pending_photoshop:          1,
    pending_dropbox:            2,
    complete:                   3,
    pending_photoshop_previews: 4,
    stopped:                    5,
    failed:                     6
  }, _prefix:             true

  belongs_to :user
  has_many :artwork_templates, inverse_of: :artwork
  has_many :templates, through: :artwork_templates, class_name: 'EnvironmentTemplate', source: :environment_template
  attr_accessor :model_templates, :regular_templates
  has_many :uploads, as: :attachable
  has_many :previews, -> { where(upload_type: 'preview') }, class_name: 'Upload', as: :attachable
  has_many :manufacturer_renders, -> { where(upload_type: 'manufacturer') }, class_name: 'Upload', as: :attachable
  has_many :dropbox_uploads
  has_many :dropbox_orderdesk_uploads, -> { joins(:upload).where(uploads: { upload_type: 'manufacturer' }) }, class_name: 'DropboxUpload'
  has_many :dropbox_logs, through: :dropbox_uploads, source: :integration_log
  has_many :integration_logs, as: :recordable
  has_one :offer, class_name: 'ArtworkOffer'

  validates :name, :description, :artwork_type, :template_type, presence: true, unless: :is_bulk_process?
  validates :tags, presence: true, on: :admin_submission, unless: :is_bulk_process?
  validate :three_or_more_tags, on: :admin_submission, unless: :is_bulk_process?
  validate :cant_unapprove
  validates_uniqueness_of :name, conditions: -> { where.not(status_on_store: :deleted) }, unless: :is_bulk_process?

  before_save :setup

  after_commit :process_approved_artwork,
               :notify!,
               :artwork_submission_notification!

  def preview_urls
    @preview_urls ||= previews_in_order.map(&:file_url)
  end

  def previews_in_order
    uploads
      .where("params->>'order' IS NOT NULL")
      .where("(params->>'for_marketing' IS NULL OR params->>'for_marketing' != 'true')")
      .order(Arel.sql("CAST(params->>'order' AS INTEGER) ASC"))
  end

  def marketing_previews
    previews.where("params->>'for_marketing' = 'true'")
  end

  # For failed environment template id`s
  def failed_environment_template_ids
    integration_logs
    .where(action: 'photoshop.render_previews', status: :failed, secondary_recordable_type: 'ArtworkEnvironmentTemplate')
    .pluck(:secondary_recordable_id)
  end

  private

  def is_bulk_process?
    return pending_form_submission?
  end

  def setup
    self.status_changed_at            = Time.current if will_save_change_to_status?
    self.submission_status_changed_at = Time.current if will_save_change_to_submission_status?
  end

  def notify!
    return unless saved_change_to_status? && (rejected? || approved?) && !for_rendering_test_process_flag?

    Notification.create!(trackable: self, key: "artwork.#{status}", user: user)
  end

  def process_approved_artwork
    # Todo - remove the boolean check and just add another submission_status
    return unless approved? && submission_status_pending? && !processing_submission_flow?

    Flows::ProcessApprovedSubmissionJob.perform_later(id)
  end

  def cant_unapprove
    return unless saved_change_to_status? && status_was == 'approved' && status != 'approved'

    errors.add(:status, 'can not be changed from approved to something else')
  end

  def three_or_more_tags
    count = tags&.split(',')&.count || 0
    return unless count < 3

    errors.add(:tags, 'must contain three or more keywords')
  end

  # For send notification emails on artist artwork submission
  def artwork_submission_notification!
    return unless saved_change_to_status? && review?

    ArtworkNotifierMailer.artwork_submission_notification(id).deliver_now
  end

end
