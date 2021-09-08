require 'rails_helper'
require 'factories_helper'

RSpec.describe Interactors::Tickets::AddComment do
  include ActiveJob::TestHelper
  include Spec::FactoriesHelper
  fixtures :all

  let(:user) { create_user }
  let(:order) { create_order({user_id: user.id}) }
  let(:ordered_assay) { order.ordered_assays.first }
  let(:ticket) do
    ticket = perform_enqueued_jobs do
     Interactors::Tickets::CreateTicket.call(
        {
          ticket_params: {title: 'My title', description: 'Some description', ordered_assay_id: ordered_assay.id},
          user: user
        }
      ).ticket
    end
    ActionMailer::Base.deliveries.clear
    ticket
  end

  subject(:context) { described_class.call(params) }

  describe '.call' do

    context 'when user creates comment' do
      let(:params) do
        {
          ticket: ticket,
          comment_params: {body: 'Some body'},
          user: user
        }
      end

      it 'creates comment' do
        expect_any_instance_of(Interactors::Tickets::NotifyAboutCommentCreation).to receive(:call).and_return(nil)

        expect(context.success?).to be true
        expect(context.comment).not_to be_nil
        expect(context.comment.body).to eq('Some body')
        expect(context.comment.user_id).to eq(user.id)
        expect(context.comment.ticket_id).to eq(ticket.id)
        expect(context.comment.persisted?).to be true
      end

      it 'notifies admins about new comment' do
        create_admin({first_name: 'Alex', email: 'admin@admin.com', email_notifications: true})
        create_admin({first_name: 'Ruslan', email: 'admin1@admin.com', email_notifications: true})
        create_admin({first_name: 'Konstantin', email: 'admin2@admin.com', email_notifications: false})

        perform_enqueued_jobs do
          expect(context.success?).to be true
        end

        deliveries = ActionMailer::Base.deliveries
        expect(deliveries.length).to eq(2)
        expect(deliveries[0].to).to eq(['admin@admin.com'])
        expect(deliveries[1].to).to eq(['admin1@admin.com'])
      end

      it 'creates event' do
        expect(context.success?).to be true
        events = Event.where(event_type: Event::COMMENT_CREATION)
        expect(events.length).to eq(1)
        event = events[0]
        expect(event.title).to eq("New comment for ticket ##{context.ticket.id}")
        expect(event.user_id).to eq(user.id)
        expect(event.order_id).to eq(order.id)
        expect(event.ordered_assay_id).to eq(ordered_assay.id)
        expect(event.meta['author']).to eq(user.full_name)
        expect(event.meta['user']).to eq(user.full_name)
        expect(event.meta['ticket_id']).to eq(context.ticket.id)
        expect(event.meta['comment_id']).to eq(context.comment.id)
      end
    end

    context 'when admin creates comment' do
      let(:admin) { create_admin(first_name: 'Alex', email: 'admin@admin.com') }

      let(:params) do
        {
          ticket: ticket,
          comment_params: {body: 'Some body'},
          admin: admin
        }
      end

      it 'creates comment' do
        expect_any_instance_of(Interactors::Tickets::NotifyAboutCommentCreation).to receive(:call).and_return(nil)

        expect(context.success?).to be true
        expect(context.comment).not_to be_nil
        expect(context.comment.body).to eq('Some body')
        expect(context.comment.admin_id).to eq(admin.id)
        expect(context.comment.ticket_id).to eq(ticket.id)
        expect(context.comment.persisted?).to be true
      end

      it 'creates event' do
        expect(context.success?).to be true
        events = Event.where(event_type: Event::COMMENT_CREATION)
        expect(events.length).to eq(1)
        event = events[0]
        expect(event.title).to eq("New comment for ticket ##{context.ticket.id}")
        expect(event.user_id).to eq(user.id)
        expect(event.order_id).to eq(order.id)
        expect(event.ordered_assay_id).to eq(ordered_assay.id)
        expect(event.meta['author']).to eq(admin.full_name)
        expect(event.meta['user']).to eq(user.full_name)
        expect(event.meta['ticket_id']).to eq(context.ticket.id)
        expect(event.meta['comment_id']).to eq(context.comment.id)
      end

      it 'notifies ticket owner about new comment' do
        create_user({first_name: 'Ruslan', email: 'user1@user.com', email_notifications: true})
        perform_enqueued_jobs do
          expect(context.success?).to be true
        end

        deliveries = ActionMailer::Base.deliveries
        expect(deliveries.length).to eq(1)
        expect(deliveries[0].to).to eq(['user@user.com'])
      end

      it 'does not notifies ticket owner if he does not want' do
        user.update!(email_notifications: false)

        perform_enqueued_jobs do
          expect(context.success?).to be true
        end

        deliveries = ActionMailer::Base.deliveries
        expect(deliveries.length).to eq(0)
      end
    end

    context 'when comment is invalid' do
      context 'blank body' do
        let(:params) do
          {
            ticket: ticket,
            comment_params: {body: '  '},
            user: user
          }
        end

        it 'fails' do
          expect_any_instance_of(Interactors::Tickets::NotifyAboutCommentCreation).not_to receive(:call)

          expect(context.success?).to be false
          expect(context.comment).not_to be_nil
          expect(context.comment.valid?).to be false
        end
      end
    end

    context 'when ticket created for order' do
      let(:ticket) do
        ticket = perform_enqueued_jobs do
          Interactors::Tickets::CreateTicket.call(
            {
              ticket_params: {title: 'My title', description: 'Some description', order_id: order.id},
              user: user
            }
          ).ticket
        end
        ActionMailer::Base.deliveries.clear
        ticket
      end

      let(:params) do
        {
          ticket: ticket,
          comment_params: {body: 'Some body'},
          user: user
        }
      end

      it 'creates event' do
        expect(context.success?).to be true
        events = Event.where(event_type: Event::COMMENT_CREATION)
        expect(events.length).to eq(1)
        event = events[0]
        expect(event.title).to eq("New comment for ticket ##{context.ticket.id}")
        expect(event.user_id).to eq(user.id)
        expect(event.order_id).to eq(order.id)
        expect(event.ordered_assay_id).to be_nil
        expect(event.meta['author']).to eq(user.full_name)
        expect(event.meta['user']).to eq(user.full_name)
        expect(event.meta['ticket_id']).to eq(context.ticket.id)
        expect(event.meta['comment_id']).to eq(context.comment.id)
      end
    end

    context 'when ticket is closed' do
      let(:params) do
        ticket.status = Ticket::CLOSED_STATUS
        ticket.save!
        {
          ticket: ticket,
          comment_params: {body: 'Comment body'},
          user: user
        }
      end

      it 'fails' do
        expect_any_instance_of(Interactors::Tickets::NotifyAboutCommentCreation).not_to receive(:call)

        expect(context.success?).to be false
        expect(context.message).to eq('Ticket is closed')
      end
    end
  end
end
