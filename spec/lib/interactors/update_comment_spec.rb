require 'rails_helper'
require 'factories_helper'

RSpec.describe Interactors::Tickets::UpdateComment do
  include Spec::FactoriesHelper
  fixtures :all

  let(:user) { create_user }
  let(:order) { create_order({user_id: user.id}) }
  let(:ordered_assay) { order.ordered_assays.first }
  let(:ticket) do
    Interactors::Tickets::CreateTicket.call(
      {
        ticket_params: {title: 'My title', description: 'Some description', ordered_assay_id: ordered_assay.id},
        user: user
      }
    ).ticket
  end
  let(:comment) do
    Interactors::Tickets::AddComment.call(
      {
        ticket: ticket,
        user: user,
        comment_params: {body: 'My body'}
      }
    ).comment
  end
  subject(:context) { described_class.call(params) }

  describe '.call' do

    context 'when comment is valid' do
      let(:params) do
        {
          comment: comment,
          comment_params: { body: 'New body' }
        }
      end

      it 'update comment' do
        expect(context.success?).to be true
        expect(context.comment.body).to eq('New body')
        expect(context.comment.persisted?).to be true
      end
    end

    context 'when comment is invalid' do
      let(:params) do
        {
          comment: comment,
          comment_params: { body: ' ' }
        }
      end

      it 'fails' do
        expect(context.success?).to be false
        expect(context.comment.valid?).to be false
      end
    end

    context 'when ticket is closed' do
      let(:params) do
        result = {
          comment: comment,
          comment_params: { body: 'New body' }
        }
        ticket.status = Ticket::CLOSED_STATUS
        ticket.save!
        result
      end

      it 'fails' do
        expect(context.success?).to be false
        expect(context.message).to eq('Ticket is closed')
      end
    end
  end
end
