class Users::RegistrationsController < Devise::RegistrationsController
  before_action :set_avatar, only: [:edit, :update]

  # POST /resource
  # NOTE This needs the whole action from Devise to insert subscription creation at the right time.
  def create
    build_resource(sign_up_params)
    resource.save
    yield resource if block_given?
    if resource.persisted?
      create_stripe_subscription(resource)
      if resource.active_for_authentication?
        set_flash_message! :notice, :signed_up
        sign_up(resource_name, resource)
        respond_with resource, location: after_sign_up_path_for(resource)
      else
        set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
        expire_data_after_sign_in!
        respond_with resource, location: after_inactive_sign_up_path_for(resource)
      end
    else
      clean_up_passwords resource
      set_minimum_password_length
      respond_with resource
    end
  end

  def destroy
    resource.destroy
    Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name)
    set_flash_message! :notice, :destroyed
    yield resource if block_given?
    redirect_to cancelled_path
  end

  protected

    def after_update_path_for(resource)
      edit_user_registration_path
    end

    def after_sign_up_path_for(resource)
      if resource.subscribed?
        dashboard_path
      else
        new_subscription_path
      end
    end

  private
    def set_avatar
      @avatar = resource.avatar || Avatar.new(user_id: resource.id)
    end

    # TODO Check if this can be done in before_create callback in user model
    def create_stripe_subscription(resource)
      customer = Stripe::Customer.create(email: resource.email)

      begin
        # Change this to a selected plan if you have more than 1
        plan = Stripe::Plan.list(limit: 1).first
        subscription = customer.subscriptions.create(
          source: params[:stripeToken],
          plan: plan.id,
          trial_end: Rails.env.try(:trial_period) || 14.days.from_now.to_i
        )
        options = {
          stripe_id: customer.id,
          stripe_subscription_id: subscription.id,
        }
        resource.update(options)
      rescue => e
        puts "Log this error! #{e.inspect}"
      end
    end
end