module Interactors
  module Tickets
    class DeleteComment
      include Interactor

      def call
        context.fail!(message: 'Ticket is closed') if ticket.closed?

        context.comment.destroy
      end

      private

      def user
        context.user
      end

      def ticket
        context.comment.ticket
      end
    end
  end
end