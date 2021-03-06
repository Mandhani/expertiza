class ApplicationController < ActionController::Base
  include AccessHelper

  # You want to get exceptions in development, but not in production.
  unless Rails.application.config.consider_all_requests_local
    rescue_from ActionView::MissingTemplate do |_exception|
      redirect_to root_path
    end
  end

  # forcing SSL only in the production mode
  force_ssl if Rails.env.production?

  helper_method :current_user, :current_user_role?
  protect_from_forgery with: :exception
  before_action :set_time_zone
  before_action :authorize
  before_action :filter_utf8
  before_action :set_locale

  def filter_utf8
    remove_non_utf8(params)
  end

  def self.verify(_args); end

  def current_user_role?
    current_user.role.name
  end

  def current_role_name
    current_role.try :name
  end

  def current_role
    current_user.try :role
  end

  helper_method :current_user_role?

  def user_for_paper_trail
    session[:user].try :id if session[:user]
  end

  def undo_link(message)
    version = Version.where('whodunnit = ?', session[:user].id).last
    return unless version.try(:created_at) && Time.now.in_time_zone - version.created_at < 5.0
    link_name = params[:redo] == 'true' ? 'redo' : 'undo'
    message + "<a href = #{url_for(controller: :versions, action: :revert, id: version.id, redo: !params[:redo])}>#{link_name}</a>"
  end

  def are_needed_authorizations_present?(id, *authorizations)
    participant = Participant.find_by(id: id)
    return false if participant.nil?
    authorization = Participant.get_authorization(participant.can_submit, participant.can_review, participant.can_take_quiz)
    !authorizations.include?(authorization)
  end

  private

  def set_locale
    # Only students with course having language set should have session[:locale] set
    if(logged_in? && current_user_role? && current_user_role.student?)
      # If params is set, means that language was requested. Reset it.
      if !params[:locale].nil?
        session[:user_locale] = params[:locale]
      elsif session[:user_locale].nil? # Set the session[:locale] for student
        set_new_locale_for_student
      end
      @locale ||= session[:user_locale] || session[:locale] || I18n.default_locale
      I18n.locale = session[:locale] = @locale
    else
      I18n.locale = I18n.default_locale
    end
  end

  def set_new_locale_for_student
    # Check student task view and set locale accordingly.
    if !params[:id].nil? || !params[:student_id].nil?
      participant_id = params[:id] || params[:student_id]
      participant = AssignmentParticipant.find_by(id: participant_id)
      # If id or student_id not correct, revert to default locale based on courses.
      if participant.nil?
        session[:locale] = find_locale_from_courses
        return
      end
      assignment = participant.assignment
      if !assignment.course.nil?
        new_locale = assignment.course.locale
        if !new_locale.nil?
          session[:locale] = new_locale
        else
          session[:locale] = I18n.default_locale
        end
      else
        session[:locale] = I18n.default_locale
      end
    else # Set locale to best default possible to all other student pages
      session[:locale] = find_locale_from_courses
    end
  end

  def find_locale_from_courses
    courseParticipants = CourseParticipant.where(user_id: current_user.id)
    courseParticipantsLocales = courseParticipants.map { |cp| cp.course.locale}
    # If no tasks, then possible to have no courses assigned.
    if courseParticipantsLocales.uniq.length == 1 #&& !@tasks.empty?
      course = courseParticipants.first.course
      if course.locale?
        return course.locale
      else
        return I18n.default_locale
      end
    else
      return I18n.default_locale
    end
  end

  def default_url_options(options={})
    options
  end

  def current_user
    @current_user ||= session[:user]
  end

  helper_method :current_user

  def current_user_role
    current_user.role
  end

  alias current_user_role? current_user_role

  def logged_in?
    current_user
  end

  def redirect_back(default = :root)
    redirect_to request.env['HTTP_REFERER'] ? :back : default
  end

  def set_time_zone
    Time.zone = current_user.timezonepref if current_user
  end

  def require_user
    invalid_login_status('in') unless current_user
  end

  def require_no_user
    invalid_login_status('out') if current_user
  end

  def invalid_login_status(status)
    flash[:notice] = "You must be logged #{status} to access this page!"
    redirect_back
  end

  def is_available(user, owner_id)
    user.id == owner_id ||
        user.admin? ||
        user.super_admin?
  end

  def record_not_found
    redirect_to controller: :tree_display, action: :list
  end

  def remove_non_utf8(hash)
    # remove non-utf8 chars from hash
    hash.each_pair do |_key, value|
      if value.is_a?(Hash)
        remove_non_utf8(value)
      elsif value.is_a?(String)
        encode_opts = {
          invalid: :replace,
          undef: :replace,
          replace: ''
        }
        value.encode!(Encoding.find('UTF-8'), encode_opts)
      end
    end
  end

  protected
  
  # Use this method to validate the current user in order to avoid allowing users
  # to see unauthorized data.
  # Ex: return unless current_user_id?(params[:user_id])
  def current_user_id?(user_id)
    current_user.try(:id) == user_id
  end

  def denied(reason = nil)
    if reason
      redirect_to "/denied?reason=#{reason}"
    else
      redirect_to '/denied'
    end
  end
end
