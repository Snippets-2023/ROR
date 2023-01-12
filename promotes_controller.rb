class PromotesController < ApplicationController
  authorize_resource class: :promote
  load_resource :user

  def index
    @user = current_user

    if(@user.present?)
      
      # week widget properties    
      @today = Date.today
      @end_of_day = @today + 1.day
      @beginning_of_week = @today.at_beginning_of_week

      @shopify_collection_list = Promote::ShopifyCollectionList.new(@user.id).call('best-selling')

      @week_royalties_total =  "%0.2f"%Royalties::Calculations::DetermineRoyaltiesForUser.new(@user).call(@beginning_of_week, @end_of_day)

      @week_sales_total = Promote::SalesStats.new(@user).call(@beginning_of_week, @end_of_day)

      @week_orders_total = Promote::OrdersStats.new(@user.id).call(@beginning_of_week, @end_of_day)

      @uploads_this_week = Artwork.where(created_at: @beginning_of_week..@end_of_day, user_id: @user.id).count
      
    end
  end

end
