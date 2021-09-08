class TicketsController < UserApplicationController
  helper_method :sort_column


  def show
    @ticket = Ticket.includes(comments: [:user, :admin]).where(user: current_user).find(params[:id])
    @comment = Comment.new
  end

  def new
    order = Order.where(user: current_user).find(params[:order_id]) if params[:order_id]
    ordered_assay = OrderedAssay.where(user: current_user).find(params[:project_id]) if params[:project_id]

    if ordered_assay && !policy(ordered_assay).work_with_tickets?
      flash[:upgrade_message] = Objects::UserPlan::TICKETS_NOT_AVAILABLE_MESSAGE
      redirect_to profile_plans_path
    else
      @ticket = Ticket.new(order: order, ordered_assay: ordered_assay)
    end
  end

  def create
    result = Interactors::Tickets::CreateTicket.call(
      ticket_params: ticket_params,
      user: current_user
    )
    @ticket = result.ticket

    if result.success?
      flash[:success] = 'Ticket has been created'
      redirect_to ticket_path(@ticket)
    else
      flash[:error] = result.message
      render 'new'
    end
  end


  def add_comment
    @ticket = Ticket.includes(:ordered_assay).where(user: current_user).find(params[:id])

    result = Interactors::Tickets::AddComment.call(
      ticket: @ticket,
      user: current_user,
      comment_params: comment_params
    )
    if result.success?
      json_response = {success: true, reload: true}
      flash[:success] = 'Comment has been added'
    else
      json_response = {success: false, message: result.message, errors: result.comment&.errors}
    end

    render json: json_response
  end

  def delete_comment
    comment = Comment.includes(ticket: [:ordered_assay]).where(user: current_user).find(params[:id])

    result = Interactors::Tickets::DeleteComment.call(user: current_user, comment: comment)
    if result.success?
      json_response = {success: true, message: 'Comment has been deleted'}
    else
      json_response = {success: false, message: result.message }
    end

    render json: json_response
  end

  def update_comment
    comment = Comment.includes(ticket: [:ordered_assay]).where(user: current_user).find(params[:id])

    result = Interactors::Tickets::UpdateComment.call(
      comment_params: comment_params,
      comment: comment,
      user: current_user
    )

    if result.success?
      json_response = {success: true, message: 'Comment has been updated'}
    else
      json_response = {success: false, message: result.message, errors: result.comment&.errors}
    end

    render json: json_response
  end

  private

  def ticket_params
    params.require(:ticket).permit(:title, :description, :order_id, :ordered_assay_id)
  end

  def update_ticket_params
    params.require(:ticket).permit(:title, :description, :order_id, :ordered_assay_id)
  end

  def comment_params
    params.require(:comment).permit(:body)
  end

end
