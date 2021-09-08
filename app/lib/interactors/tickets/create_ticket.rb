module Interactors
  module Tickets
    class Create
      include Interactor

      def call
        ticket = Ticket.new(context.ticket_params)
        context.ticket = ticket

        context.fail!(message: 'Confirm your email address to create tickets. Just click the confirmation link we sent to your email.') unless context.user.confirmed?
        ticket.user = context.user
        ticket.author_user = context.user
        ticket.status = Ticket::OPEN_STATUS

        unless allowed_to_create?
          context.fail!(message: 'Could not create ticket')
        end

        context.fail! unless ticket.valid?
        ticket.save!
      end

      private

      def allowed_to_create?
        order_id = context.ticket_params[:order_id]
        ordered_assay_id = context.ticket_params[:ordered_assay_id]
        if ordered_assay_id.present?
          ordered_assay = OrderedAssay
                            .where(user_id: context.user.id)
                            .find_by_id(ordered_assay_id)
          return false unless ordered_assay

          Pundit.policy!(context.user, ordered_assay).work_with_tickets?
        elsif order_id.present?
          Order.where(user_id: context.user.id).exists?(order_id)
        else
          true
        end
      end
    end

    class NotifyAboutCreation
      include Interactor

      def call
        admins = Admin.where(email_notifications: true, role: Admin::ROLE_SUPERADMIN).pluck(:id)
        admins.each do |admin_id|
          TicketsMailer.ticket_created_email(context.ticket.id, admin_id, nil).deliver_later
        end
      end
    end

    class CreateTicket
      include Interactor::Organizer

      organize Create, Interactors::Tickets::CreateTicketEvent, NotifyAboutCreation
    end
  end
end