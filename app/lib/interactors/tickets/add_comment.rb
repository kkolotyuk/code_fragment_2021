module Interactors
  module Tickets
    class CreateComment
      include Interactor

      def call
        context.fail!(message: 'Ticket is closed') if ticket.closed?

        comment = ticket.comments.build(context.comment_params)
        comment.user = context.user
        comment.admin = context.admin
        context.comment = comment

        context.fail! unless comment.valid?

        comment.save!
      end

      private

      def ticket
        context.ticket
      end
    end

    class CreateCommentEvent
      include Interactor

      def call
        context.event = Event.create!(
          order_id: order_id,
          ordered_assay_id: ticket.ordered_assay_id,
          title: "New comment for ticket ##{ticket.id}",
          event_type: Event::COMMENT_CREATION,
          user_id: user.id,
          meta: {
            author: comment.author(false).full_name,
            user: user.full_name,
            ticket_id: ticket.id,
            comment_id: comment.id
          }
        )
      end

      private

      def order_id
        ticket.order_id || ticket.ordered_assay.order_id
      end

      def comment
        context.comment
      end

      def ticket
        context.ticket
      end

      def user
        context.user || ticket.user
      end
    end

    class NotifyAboutCommentCreation
      include Interactor

      def call
        if comment.owner_user?
          admins = Admin.where(email_notifications: true, role: Admin::ROLE_SUPERADMIN).pluck(:id)
          admins.each do |admin_id|
            TicketsMailer.comment_added_email(comment.id, admin_id, nil).deliver_later
          end
        else
          user = comment.ticket.user
          if user.email_notifications
            TicketsMailer.comment_added_email(comment.id, nil, user.id).deliver_later
          end
        end
      end

      private

      def comment
        context.comment
      end
    end

    class AddComment
      include Interactor::Organizer

      organize CreateComment, CreateCommentEvent, NotifyAboutCommentCreation
    end
  end
end