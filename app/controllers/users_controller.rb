require 'net/http'
require 'google/apis/sheets_v4'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'fileutils'

class UsersController < ApplicationController
  before_filter :skip_first_page, only: :new
  before_filter :handle_ip, only: :create

  OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'.freeze
  APPLICATION_NAME = 'Google Sheets API Ruby Quickstart'.freeze
  CREDENTIALS_PATH = 'credentials.json'.freeze
  TOKEN_PATH = 'token.yaml'.freeze
  SCOPE = Google::Apis::SheetsV4::AUTH_SPREADSHEETS

  def authorize
    client_id = Google::Auth::ClientId.from_file(CREDENTIALS_PATH)
    token_store = Google::Auth::Stores::FileTokenStore.new(file: TOKEN_PATH)
    authorizer = Google::Auth::UserAuthorizer.new(client_id, SCOPE, token_store)
    user_id = 'default'
    credentials = authorizer.get_credentials(user_id)
    if credentials.nil?
      url = authorizer.get_authorization_url(base_url: OOB_URI)
      puts 'Open the following URL in the browser and enter the ' \
         "resultinsg code after authorization:\n" + url
      code = gets
      credentials = authorizer.get_and_store_credentials_from_code(
        user_id: user_id, code: code, base_url: OOB_URI
      )
    end
    credentials
  end

  def new
    @bodyId = 'home'
    @is_mobile = mobile_device?

    @user = User.new

    respond_to do |format|
      format.html # new.html.erb
    end
  end

  def create
    ref_code = cookies[:h_ref]
    email = params[:user][:email]

    # If the user has already signed up, just redirect them to the refer page.
    @duplicate_user = User.find_by_email(email)
    if @duplicate_user
      cookies[:h_email] = { value: email }
      redirect_to '/refer-a-friend'
      return
    end

    # If the user signed up via a referral code, move the referrer up the sign-up list by one.
    @user = User.new(email: email)
    @user.referrer = User.find_by_referral_code(ref_code) if ref_code

    service = Google::Apis::SheetsV4::SheetsService.new
    service.client_options.application_name = APPLICATION_NAME
    service.authorization = authorize
    spreadsheet_id = '11hxiCSKTAlLp1CJfKndmREgXbFbZVwJl_vdbByIPPKE'
    range = 'Sheet1!A2:C'
    value_range_object = Google::Apis::SheetsV4::ValueRange.new(
      range: range,
      values: [[
        @user.email,
        @user.referrer ? @user.referrer.id : nil,
        @user.referrer ? @user.referrer.email : nil
      ]]
    )
    response = service.append_spreadsheet_value(spreadsheet_id, range, value_range_object, value_input_option: 'RAW')

    if ref_code and User.find_by_email(@user.email).blank? then
      @referrer = User.find_by_referral_code(ref_code)
      if @referrer then
        @referrer.points = @referrer.points + 1
        @referrer.save
      end
    end

    # On each user's sign-up, save their current session.
    if @user.save
      cookies[:h_email] = { value: @user.email }
      redirect_to '/refer-a-friend'
    else
      logger.info("Error saving user with email, #{email}")
      redirect_to root_path, alert: 'Something went wrong!'
    end
  end

  def refer
    @bodyId = 'refer'
    @is_mobile = mobile_device?

    @user = User.find_by_email(cookies[:h_email])

    if @user
      @total_users = User.count
      @queue_position = User.where("points >  ?", @user.points).count + User.where("points = ? AND updated_at < ?", @user.points, @user.updated_at).count + 1
    end

    respond_to do |format|
      if @user.nil?
        format.html { redirect_to root_path, alert: 'Something went wrong!' }
      else
        format.html # refer.html.erb
      end
    end
  end

  def policy
  end

  def redirect
    redirect_to root_path, status: 404
  end

  private

  def skip_first_page
    return if Rails.application.config.ended

    email = cookies[:h_email]
    if email && User.find_by_email(email)
      redirect_to '/refer-a-friend'
    else
      cookies.delete :h_email
    end
  end

  def handle_ip
    # Prevent someone from gaming the site by referring themselves.
    # Presumably, users are doing this from the same device so block
    # their ip after their ip appears three times in the database.

    address = request.env['HTTP_X_FORWARDED_FOR']
    return if address.nil?

    current_ip = IpAddress.find_by_address(address)
    if current_ip.nil?
      current_ip = IpAddress.create(address: address, count: 1)
    elsif current_ip.count > 2
      logger.info('IP address has already appeared three times in our records.
                 Redirecting user back to landing page.')
      return redirect_to root_path
    else
      current_ip.count += 1
      current_ip.save
    end
  end
end
