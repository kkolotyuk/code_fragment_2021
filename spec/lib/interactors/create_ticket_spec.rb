require 'rails_helper'
require 'factories_helper'

RSpec.describe Interactors::Tickets::CreateTicket do
  include ActiveJob::TestHelper
  include Spec::FactoriesHelper
  fixtures :all

  let(:user) { create_user }
  subject(:context) { described_class.call(params) }

  describe '.call' do
    let(:order) { create_order({user_id: user.id}) }
    context 'when ticket is invalid' do
      context 'blank title' do
        let(:params) do
          {
            ticket_params: {order_id: order.id, title: '  ', description: 'Some description'},
            user: user
          }
        end

        it 'fails' do
          expect_any_instance_of(Interactors::Tickets::NotifyAboutCreation).to_not receive(:call)

          expect(context.success?).to be false
          expect(context.ticket).not_to be_nil
          expect(context.ticket.valid?).to be false
        end
      end

      context 'blank description' do
        let(:params) do
          {
            ticket_params: {order_id: order.id, title: 'My title', description: '  '},
            user: user
          }
        end

        it 'fails' do
          expect_any_instance_of(Interactors::Tickets::NotifyAboutCreation).to_not receive(:call)

          expect(context.success?).to be false
          expect(context.ticket).not_to be_nil
          expect(context.ticket.valid?).to be false
        end
      end
    end

    context 'when ticket is valid' do
      let(:params) do
        {
          ticket_params: {order_id: order.id, title: 'My title', description: 'Some description'},
          user: user
        }
      end

      it 'creates new ticket' do
        expect_any_instance_of(Interactors::Tickets::NotifyAboutCreation).to receive(:call).and_return(nil)

        expect(context.success?).to be true
        expect(context.ticket).not_to be_nil
        expect(context.ticket.persisted?).to be true
        expect(context.ticket.author_user_id).to eq(user.id)
        expect(context.ticket.status).to eq(Ticket::OPEN_STATUS)
      end

      it 'creates event' do
        expect(context.success?).to be true
        events = Event.where(event_type: Event::TICKET_CREATION)
        expect(events.length).to eq(1)
        event = events[0]
        expect(event.title).to eq("Ticket ##{context.ticket.id} created")
        expect(event.user_id).to eq(user.id)
        expect(event.order_id).to eq(order.id)
        expect(event.meta['author']).to eq(user.full_name)
        expect(event.meta['user']).to eq(user.full_name)
        expect(event.meta['ticket_id']).to eq(context.ticket.id)
      end

      it 'notifies admins about creation' do
        create_admin({email: 'admin@admin.com', email_notifications: true})
        create_admin({email: 'admin1@admin.com', email_notifications: true})
        create_admin({email: 'admin2@admin.com', email_notifications: false})

        perform_enqueued_jobs do
          expect(context.success?).to be true
        end

        deliveries = ActionMailer::Base.deliveries
        expect(deliveries.length).to eq(2)
        expect(deliveries[0].to).to eq(['admin@admin.com'])
        expect(deliveries[1].to).to eq(['admin1@admin.com'])
      end
    end

    context 'when creates ticket for order' do
      context 'when order owner tries to create ticket' do
        let(:order) { create_order({user_id: user.id}) }
        let(:params) do
          {
            ticket_params: {order_id: order.id, title: 'My title', description: 'Some description'},
            user: user
          }
        end

        it 'creates new ticket' do
          expect_any_instance_of(Interactors::Tickets::NotifyAboutCreation).to receive(:call).and_return(nil)

          expect(context.success?).to be true
          expect(context.ticket).not_to be_nil
          expect(context.ticket.author_user_id).to eq(user.id)
          expect(context.ticket.order_id).to eq(order.id)
          expect(context.ticket.ordered_assay_id).to be nil
          expect(context.ticket.status).to eq(Ticket::OPEN_STATUS)
          expect(context.ticket.persisted?).to be true
        end

        it 'creates event' do
          expect(context.success?).to be true
          events = Event.where(event_type: Event::TICKET_CREATION)
          expect(events.length).to eq(1)
          event = events[0]
          expect(event.title).to eq("Ticket ##{context.ticket.id} created")
          expect(event.user_id).to eq(user.id)
          expect(event.order_id).to eq(order.id)
          expect(event.meta['author']).to eq(user.full_name)
          expect(event.meta['user']).to eq(user.full_name)
          expect(event.meta['ticket_id']).to eq(context.ticket.id)
        end
      end

      context 'when not order owner tries to create ticket' do
        let(:another_user) { create_user({first_name: 'Alex', email: 'another@user.com'}) }
        let(:order) { create_order({user_id: another_user.id}) }
        let(:params) do
          {
            ticket_params: {order_id: order.id, title: 'My title', description: 'Some description'},
            user: user
          }
        end

        it 'does not allow to create ticket' do
          expect_any_instance_of(Interactors::Tickets::NotifyAboutCreation).to_not receive(:call)

          expect(context.success?).to be false
          expect(context.ticket).not_to be_nil
          expect(context.ticket.author_user_id).to eq(user.id)
          expect(context.ticket.order_id).to eq(order.id)
          expect(context.ticket.persisted?).to be false
          expect(context.message).to eq 'Could not create ticket'
        end
      end
    end

    context 'when creates ticket for project' do
      context 'when project owner tries to create ticket' do
        let(:order) { create_order({user_id: user.id}) }
        let(:ordered_assay) { order.ordered_assays.first }
        let(:params) do
          {
            ticket_params: {ordered_assay_id: ordered_assay.id, title: 'My title', description: 'Some description'},
            user: user
          }
        end

        it 'creates new ticket' do
          expect_any_instance_of(Interactors::Tickets::NotifyAboutCreation).to receive(:call).and_return(nil)

          expect(context.success?).to be true
          expect(context.ticket).not_to be_nil
          expect(context.ticket.id).not_to be_nil
          expect(context.ticket.author_user_id).to eq(user.id)
          expect(context.ticket.user_id).to eq(user.id)
          expect(context.ticket.order_id).to be nil
          expect(context.ticket.ordered_assay_id).to eq(ordered_assay.id)
          expect(context.ticket.status).to eq(Ticket::OPEN_STATUS)
        end

        it 'creates event' do
          expect(context.success?).to be true
          events = Event.where(event_type: Event::TICKET_CREATION)
          expect(events.length).to eq(1)
          event = events[0]
          expect(event.title).to eq("Ticket ##{context.ticket.id} created")
          expect(event.user_id).to eq(user.id)
          expect(event.order_id).to eq(order.id)
          expect(event.meta['author']).to eq(user.full_name)
          expect(event.meta['user']).to eq(user.full_name)
          expect(event.meta['ticket_id']).to eq(context.ticket.id)
        end
      end

      context 'when not project owner tries to create ticket' do
        let(:another_user) { create_user({first_name: 'Alex', email: 'another@user.com'}) }
        let(:order) { create_order({user_id: another_user.id}) }
        let(:ordered_assay) { order.ordered_assays.first }
        let(:params) do
          {
            ticket_params: {ordered_assay_id: ordered_assay.id, title: 'My title', description: 'Some description'},
            user: user
          }
        end

        it 'does not allow to create ticket' do
          expect_any_instance_of(Interactors::Tickets::NotifyAboutCreation).to_not receive(:call)

          expect(context.success?).to be false
          expect(context.ticket).not_to be_nil
          expect(context.ticket.author_user_id).to eq(user.id)
          expect(context.ticket.order_id).to be_nil
          expect(context.ticket.ordered_assay_id).to eq(ordered_assay.id)
          expect(context.ticket.persisted?).to be false
          expect(context.message).to eq 'Could not create ticket'
        end
      end

      context 'when user plan does not allow to create project ticket' do
        let(:order) { create_order({user_id: user.id}) }
        let(:ordered_assay) do
          oa = order.ordered_assays.first
          oa.project_status = OrderedAssay::PROJECT_STATUS_COMPLETE
          oa.completed_at = Time.now - 31.days
          oa.save!
          oa
        end
        let(:params) do
          {
            ticket_params: {ordered_assay_id: ordered_assay.id, title: 'My title', description: 'Some description'},
            user: user
          }
        end

        it 'fails' do
          expect_any_instance_of(Interactors::Tickets::NotifyAboutCreation).to_not receive(:call)

          expect(context.success?).to be false
          expect(context.message).to eq 'Could not create ticket'
        end
      end

      context 'when user is not confirmed' do
        let(:user) { create_user({confirmed_at: nil}) }
        let(:params) do
          {
            ticket_params: {title: 'My title', description: 'Some description'},
            user: user
          }
        end

        it 'fails' do
          expect(context.success?).to be false
          expect(context.message).to eq 'Confirm your email address to create tickets. Just click the confirmation link we sent to your email.'
        end
      end
    end
  end
end
