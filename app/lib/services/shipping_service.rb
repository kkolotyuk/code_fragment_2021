module Services
  class ShippingService
    # Used to find suitable rate for shipping
    SHIPPING_SERVICE_LEVEL = 'fedex_priority_overnight'

    SHIPPO_SUCCESS_STATUS = 'SUCCESS'

    def register_tracking_webhook(carrier, tracking_number)
      with_shippo_handler(false) do
        Shippo::Track::create(carrier: carrier, tracking_number: tracking_number)
        return true
      end
    end

    def start_shipment(order)
      with_shippo_handler do
        if order.shipping_with_kit?
          create_two_legs_shipment(order)
        elsif order.shipping_without_kit? || order.sender_pays?
          create_one_leg_shipment(order)
        end
      end
    end

    def fetch_label_url(transaction_id)
      with_shippo_handler(nil) do
        Shippo::Transaction.get(transaction_id).label_url.presence
      end
    end


    # Estimate price of shipping samples from user to
    # bioproximity
    def estimate_shipping_price(order)
      with_shippo_handler do
        shipment_return = Shippo::Shipment.create(
          :address_from => user_address(order),
          :address_to => bioproximity_shippo_address,
          :carrier_accounts => [Credentials[:fedex_carrier_id]],
          :parcels => leg_2_parcel(order),
          :metadata => "Order ##{order.id}",
          :async => false
        )

        if shipment_return[:status] == SHIPPO_SUCCESS_STATUS
          return_rate = find_rate(shipment_return)
          if return_rate
            return Money.from_amount(BigDecimal(return_rate.amount))
          else
            Notifiers::ErrorsNotifier.notify("Can not find suitable rate for shipping. Order ##{order.id}")
            return nil
          end
        else
          Notifiers::ErrorsNotifier.notify("Invalid shippo shipment object for order", {order_id: order.id, shipment: shipment_return.to_hash})
          return nil
        end
      end
    end

    def user_address(order)
      {
        name: order.user.full_name,
        street1: order.user.shipping_address.address1,
        street2: order.user.shipping_address.address2,
        city: order.user.shipping_address.city,
        state: order.user.shipping_address.state,
        zip: order.user.shipping_address.zip,
        country: order.user.shipping_address.country,
        phone: order.user.shipping_address.phone || order.user.phone,
        email: order.user.email
      }
    end

    def bioproximity_shippo_address
      {
        name:    bioproximity_address.name,
        company: bioproximity_address.company,
        street1: bioproximity_address.address1,
        street2: bioproximity_address.address2,
        city:    bioproximity_address.city,
        state:   bioproximity_address.state,
        zip:     bioproximity_address.zip,
        country: bioproximity_address.country,
        phone:   bioproximity_address.phone,
        email:   bioproximity_address.email
      }
    end

    def bioproximity_address
      @bioproximity_address ||= BioproximityAddress.first
    end

    # Address is a Hash with fields:
    #  - name
    #  - company
    #  - street1
    #  - street2
    #  - city
    #  - state
    #  - zip
    #  - country
    #  - email
    #  - phone
    def address_validation(address)
      with_shippo_handler('Address validation service is not available. Please try later.') do
        begin
          shippo_address = Shippo::Address.create(address.merge(validate: true))
          unless shippo_address&.validation_results&.is_valid
            if shippo_address&.validation_results&.messages&.any?
              return shippo_address.validation_results.messages.map { |m| m['text'] }.join(' ')
            else
              return 'Address is not valid'
            end
          end
          unless shippo_address.is_complete
            return 'Address is not fully entered'
          end
        rescue Shippo::Exceptions::APIServerError => e
          JSON.parse(e.response).values.flatten.join(' ')
        end
      end
    end

    private

    def create_first_leg_transaction(order)
      shipment = {
        address_from: bioproximity_shippo_address,
        address_to: user_address(order),
        parcels: leg_1_parcel(order),
        metadata: "Leg 1, Order ##{order.id}",
      }
      if order.leg_one_shipment.submission_date
        shipment[:shipment_date] = order.leg_one_shipment.submission_date.to_time.iso8601
      end

      Shippo::Transaction.create(
        shipment: shipment,
        metadata: "Leg 1, Order ##{order.id}",
        label_file_type: 'PDF',
        carrier_account: Credentials[:fedex_carrier_id],
        servicelevel_token: SHIPPING_SERVICE_LEVEL,
        async: false
      )
    end

    def create_one_leg_shipment(order)
      metadata = "Without shipping kit.#{order.sender_pays? ? ' Sender pays. ' : ' '}Order ##{order.id}"
      shipment = {
        address_from: user_address(order),
        address_to: bioproximity_shippo_address,
        parcels: leg_2_parcel(order),
        metadata: metadata,
      }
      if order.leg_two_shipment.submission_date
        shipment[:shipment_date] = order.leg_two_shipment.submission_date.to_time.iso8601
      end
      if order.sender_pays?
        shipment[:extra] = {
          billing: {
            type: "SENDER",
            account: order.leg_two_shipment.account_number
          }
        }
      end
      transaction = Shippo::Transaction.create(
        shipment: shipment,
        metadata: metadata,
        label_file_type: 'PDF',
        carrier_account: Credentials[:fedex_carrier_id],
        servicelevel_token: SHIPPING_SERVICE_LEVEL,
        async: false
      )
      if transaction[:status] == SHIPPO_SUCCESS_STATUS
        result = {
          leg_1_transaction_id: nil,
          leg_1_tracking_number: nil,
          leg_1_tracking_url: nil,
          leg_2_transaction_id: transaction.object.id,
          leg_2_tracking_number: transaction.tracking_number,
          leg_2_tracking_url: transaction.tracking_url_provider
        }
        Rails.logger.info("Shipping transactions for order ##{order.id} has been generated: #{result}")
        return result
      else
        Notifiers::ErrorsNotifier.notify("Unsuccess shippo leg 2 transaction object creation.",
                                        {order_id: order.id, transaction: transaction.to_hash})
        return nil
      end
    end

    def create_two_legs_shipment(order)
      transaction = create_first_leg_transaction(order)
      if transaction[:status] == SHIPPO_SUCCESS_STATUS
        transaction_return = Shippo::Transaction.create(
          shipment: {
            address_from: bioproximity_shippo_address,
            address_to: user_address(order),
            parcels: leg_2_parcel(order),
            extra: {is_return: true},
            metadata: "Leg 2, Order ##{order.id}",
          },
          metadata: "Leg 2, Order ##{order.id}",
          label_file_type: 'PDF',
          carrier_account: Credentials[:fedex_carrier_id],
          servicelevel_token: SHIPPING_SERVICE_LEVEL,
          async: false
        )

        if transaction_return[:status] == SHIPPO_SUCCESS_STATUS
          result = {
            leg_1_transaction_id: transaction.object.id,
            leg_1_tracking_number: transaction.tracking_number,
            leg_1_tracking_url: transaction.tracking_url_provider,
            leg_2_transaction_id: transaction_return.object.id,
            leg_2_tracking_number: transaction_return.tracking_number,
            leg_2_tracking_url: transaction_return.tracking_url_provider
          }
          Rails.logger.info("Shipping transactions for order ##{order.id} has been generated: #{result}")
          return result
        else
          Rails.logger.error("Unsuccess shippo leg 2 transaction object for order ##{order.id}. Shipment: #{transaction_return.to_hash}")
          Notifiers::ErrorsNotifier.notify("Unsuccess shippo leg 2 transaction object creation.",
                                          {order_id: order.id, transaction: transaction_return.to_hash})
          Rails.logger.info("Trying to refund leg 1 transaction: #{transaction.object.id}")
          refund = with_shippo_handler do
            Shippo::Refund.create(transaction: transaction.object.id, async: false)
          end
          if refund.nil?
            Rails.logger.error("Refund of leg 1 Shippo transaction #{transaction.object.id} failed.")
            Notifiers::ErrorsNotifier.notify("Refund of leg 1 Shippo transaction failed.",
                                            {transaction: transaction.to_hash})
          elsif refund[:status] == SHIPPO_SUCCESS_STATUS
            Rails.logger.info("Leg 1 transaction #{transactin.object.id} has been refunded")
          else
            Rails.logger.error("Refund of leg 1 transaction #{transaction.object.id} failed: #{refund.to_hash}")
            Notifiers::ErrorsNotifier.notify("Refund of leg 1 Shippo transaction failed.",
                                            {transaction: transaction.to_hash, refund: refund.to_hash})
          end
          return nil
        end
      else
        Rails.logger.error("Invalid shippo leg 1 transaction object for order ##{order.id}. Shipment: #{transaction.to_hash}")
        Notifiers::ErrorsNotifier.notify("Invalid shippo leg 1 transaction object.",
                                        {transaction: transaction.to_hash, order_id: order.id})
        return nil
      end
    end

    def leg_1_parcel(order)
      {
        length: 12,
        width: 9,
        height: 9,
        distance_unit: :in,
        weight: 1,
        mass_unit: :lb
      }
    end

    def leg_2_parcel(order)
      {
        length: 12,
        width: 9,
        height: 9,
        distance_unit: :in,
        weight: 10,
        mass_unit: :lb
      }
    end

    def find_rate(shipment)
      shipment.rates.find { |rate| rate.servicelevel.token == SHIPPING_SERVICE_LEVEL }
    end

    def with_shippo_handler(output = nil)
      yield
    rescue Shippo::Exceptions::Error => e
      Notifiers::ErrorsNotifier.notify("Unexpected error during interaction with Shippo API", {error: "#{e}"})
      Rails.logger.error("Unexpected error during interaction with Shippo API: #{e}")
      return output
    end
  end
end
