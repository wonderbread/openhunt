class ProjectsController < ApplicationController
  before_filter :require_user, only: [:new, :create, :validate, :vote_confirm, :vote, :unvote, :hide, :unhide, :edit, :update]
  before_filter :check_existing_project, only: [:new, :create]

  def index
    @bucket = Project.bucket(current_now)
    load_bucket(@bucket)
    @feed_updated_at = @projects.sort { |x, y| x.updated_at.to_i <=> y.updated_at.to_i }
                                .reverse.first.updated_at rescue DateTime.now
  end

  def recent
    @projects = Project.recent
  end

  def bucket
    @bucket = params[:bucket]
    load_bucket(@bucket)

    if params[:partial]
      if Project.end_of_buckets?(@bucket)
        render partial: "projects/end_of_buckets", locals: {
          time: Project.parse_bucket(@bucket)
        }
      else
        render partial: "projects/projects_for_bucket", locals: {
          time: Project.parse_bucket(@bucket),
          projects: @projects
        }
      end
    else
      render
    end
  end

  def vote_confirm
    load_project
  end

  def vote
    load_project

    current_user.vote(@project)

    respond_to do |format|
      format.html do
        flash[:message] = "Your vote has been counted."

        # TODO: redirect to the project detail page instead
        redirect_to "/"
      end
      format.json do
        render json: @project, root: "project"
      end
    end

  end

  def unvote
    load_project

    current_user.unvote(@project)

    respond_to do |format|
      format.html do
        flash[:message] = "Your vote has been removed."

        # TODO: redirect to the project detail page instead
        redirect_to "/"
      end
      format.json do
        render json: @project, root: "project"
      end
    end

  end

  def new

  end

  def create
    form = ProjectForm.new(params)
    form.ensure_http_on_url

    if form.valid?
      project = Project.new(form.attributes)
      project.user = current_user
      project.save!
      current_user.vote(project)
      redirect_to "/"
    else
      @errors = form.errors
      render :new
    end
  end

  def edit
    load_project
    return unless check_permissions
  end

  # PATCH /update/:slug, data: { ... }
  def update
    load_project
    return unless check_permissions

    result = current_user.update_project(@project, project_params)

    if result.success?
      url = "/detail/#{@project.slug}"
      if result.audit_log.present?
        redirect_to "/audit/#{result.audit_log.id}/edit?redirect_url=#{url}"
      else
        redirect_to url
      end
    else
      @errors = result.errors
      render :edit
    end
  end

  def hide
    load_project
    result = current_user.hide_project(@project)
    redirect_url = "/detail/#{@project.slug}"
    redirect_to "/audit/#{result.id}/edit?redirect_url=#{redirect_url}"
  end

  def unhide
    load_project
    result = current_user.unhide_project(@project)
    redirect_url = "/detail/#{@project.slug}"
    redirect_to "/audit/#{result.id}/edit?redirect_url=#{redirect_url}"
  end

  def detail
    load_project
    load_feedbacks
    load_my_feedback

    if params[:partial]
      render partial: "projects/detail", project: @project, feedback: @feedback
    else
      flash.keep
      redirect_to "/#open=#{@project.slug}"
    end
  end

  def set_feedback
    load_project
    load_my_feedback

    @feedback ||= Feedback.new
    @feedback.user_id = current_user.try(:id)
    @feedback.project_id = @project.id
    @feedback.body = params[:body].presence || ""
    if current_user.present?
      @feedback.anonymous = (params[:anonymous] == "true")
    else
      @feedback.anonymous = true
    end
    @feedback.anon_user_hash = anon_user_hash

    if @feedback.save
      respond_to do |format|
        format.html do
          flash[:notice] = "Feedback was saved. Thanks!"
          redirect_to "/detail/#{@project.id}"
        end
        format.json do
          render json: @feedback, root: "feedback"
        end
      end
    else
      respond_to do |format|
        format.html do
          flash[:alert] = "Unable to save feedback."
          redirect_to "/detail/#{@project.id}"
        end
        format.json do
          render json: {
            errors: @feedback.errors
          }
        end
      end
    end
  end

  def validate_project
    # TODO: validate project fields (name, url, description), via ajax
  end

  protected

  def load_project
    @project = Project.where(slug: params[:slug]).first
  end

  def load_feedbacks
    if current_user.try(:project_owner?, @project)
      @feedbacks = @project.feedbacks.includes(:user).order(:created_at => :desc)
    end
  end

  def load_my_feedback
    if current_user.present?
      @my_feedback = Feedback.where({
        user_id: current_user.id,
        project_id: @project.id
      }).first
    else
      @my_feedback = Feedback.where({
        anon_user_hash: anon_user_hash,
        project_id: @project.id
      }).first
    end
  end

  def load_bucket(bucket)
    @projects = Project.for_bucket(bucket).where(hidden: false).includes(:user).to_a
    if current_user.present?
      @vote_ids = current_user.match_votes(@projects.map(&:id))
    end
  end

  def check_permissions
    if current_user.can_update?(@project)
      return true
    else
      redirect_to "/detail/#{@project.slug}"
      return false
    end
  end

  def check_existing_project
    if !moderator? and current_user.submitted_project_today?
      render :already_submitted
      return false
    else
      return true
    end
  end

  def project_params
    params.permit(:name, :url, :description)
  end
end
