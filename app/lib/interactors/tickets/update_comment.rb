module Interactors
  module Tickets
    class UpdateComment
      include Interactor

      def call
        context.fail!(message: 'Ticket is closed') if ticket.closed?
        context.comment.update(context.comment_params)
        context.fail! unless context.comment.valid?
      end

      private

      def ticket
        context.comment.ticket
      end
    end
  end
end