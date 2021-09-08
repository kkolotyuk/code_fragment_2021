module Services
  class PaymentService
    CURRENCY = 'usd'

    CARD_SOURCE         = 'card'
    BANK_ACCOUNT_SOURCE = 'bank_account'
    ACCOUNT_SOURCE      = 'account'
    OFFLINE_SOURCE      = 'offline'

    SOURCES = [CARD_SOURCE, BANK_ACCOUNT_SOURCE, OFFLINE_SOURCE, ACCOUNT_SOURCE]

    REGISTER_ACH_MESSAGE = 'Please register your bank account to use ACH payments.'
    FUND_ACCOUNT_MESSAGE = 'Not enough money. Please fund your account.'

    def define_source(charge)
      if charge && charge[:source]
        if charge[:source][:object] == 'card'
          CARD_SOURCE
        elsif charge[:source][:object] == 'bank_account'
          BANK_ACCOUNT_SOURCE
        end
      end
    end

    def fetch_net(payment)
      if payment.charge_id.present?
        c = Stripe::Charge.retrieve(payment.charge_id)
        t = Stripe::BalanceTransaction.retrieve(c.balance_transaction)
        Money.new(t.net)
      else
        payment.value_m
      end
    end

    def create_order_session(order, customer_email = nil, amount = nil, success_url = nil, cancel_url = nil, ip = nil)
      Stripe::Checkout::Session.create(
        payment_method_types: ['card'],
        payment_intent_data: { # the values below will be copied to Charge object by Stripe
          metadata: order_payment_metadata(order, ip),
          description: "Payment for order ##{order.id}"
        },
        customer_email: customer_email,
        line_items: [{
          name: "Order ##{order.id}",
          amount: amount || order.invoice.total,
          currency: Services::PaymentService::CURRENCY,
          quantity: 1,
        }],
        success_url: success_url || Rails.application.routes.url_helpers.order_url(order),
        cancel_url: cancel_url || Rails.application.routes.url_helpers.order_url(order)
        )
    end

    def create_plan_session(user, plan, customer_email = nil, amount = nil)
      Stripe::Checkout::Session.create(
        payment_method_types: ['card'],
        payment_intent_data: { # the values below will be copied to Charge object by Stripe
          metadata: user_plan_payment_metadata(user, plan.code),
          description: "Payment for #{plan.code} plan of user ##{user.id}"
        },
        customer_email: customer_email,
        line_items: [{
           name: "User plan #{plan.name}",
           amount: amount || plan.price.cents,
           currency: Services::PaymentService::CURRENCY,
           quantity: 1,
         }],
        success_url: Rails.application.routes.url_helpers.profile_plans_url,
        cancel_url: Rails.application.routes.url_helpers.profile_change_plan_url(plan.code)
      )
    end

    def create_account_fund_session(user_id, amount, customer_email = nil, account_fund_id = nil)
      Stripe::Checkout::Session.create(
        payment_method_types: ['card'],
        payment_intent_data: { # the values below will be copied to Charge object by Stripe
          metadata: account_fund_metadata(user_id, account_fund_id),
          description: "Account fund for user ##{user_id}"
        },
        customer_email: customer_email,
        line_items: [{
          name: "Account fund",
          amount: amount,
          currency: Services::PaymentService::CURRENCY,
          quantity: 1,
        }],
        success_url: Rails.application.routes.url_helpers.account_url,
        cancel_url: Rails.application.routes.url_helpers.account_url
      )
    end

    # This JSON we send to payment system to associate the charge with our entity.
    def order_payment_metadata(order, ip = nil)
      result = {
        'order_id' => order.id,
        'shipping' => order.shipping_type,
        'type' => Interactors::Orders::PayOrder::PAYMENT_TYPE
      }
      if ip.present?
        result['IP'] = ip
      end
      result
    end

    # This JSON we send to payment system to associate the charge with our entity.
    def user_plan_payment_metadata(user, plan_code)
      {
        'user_id' => user.id,
        'plan' => plan_code,
        'type' => Interactors::Users::PayPlan::PAYMENT_TYPE
      }
    end

    # This JSON we send to payment system to associate the charge with our entity.
    def account_fund_metadata(user_id, account_fund_id = nil)
      {
        'user_id' => user_id,
        'account_fund_id' => account_fund_id,
        'type' => Interactors::Users::FundUserAccount::PAYMENT_TYPE
      }
    end
  end
end
