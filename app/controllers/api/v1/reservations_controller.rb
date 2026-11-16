# app/controllers/api/v1/reservations_controller.rb
module Api
  module V1
    class ReservationsController < ApplicationController
      before_action :authenticate_user!
      
        def index
          reservations = current_user.reservations
                                    .includes(:event, tickets: :ticket_type)
                                    .order(created_at: :desc)

          render json: reservations.map { |reservation|
            {
              id: reservation.id,
              event: {
                id: reservation.event.id,
                name: reservation.event.name
              },
              status: reservation.status,
              confirmation_code: reservation.confirmation_code,
              created_at: reservation.created_at,
              tickets: reservation.tickets.map { |ticket|
                {
                  id: ticket.id,
                  ticket_type: ticket.ticket_type.name,
                  attendee_name: ticket.attendee_name,
                  attendee_email: ticket.attendee_email
                }
              }
            }
          }, status: :ok
        end
    

      def show
        reservation = Reservation.find(params[:id])
        render json: ReservationSerializer.new(reservation).as_json
      end

      def create
        if tickets_params.blank?
          return render json: {
            error: "Reservation must contain at least one ticket"
          }, status: :unprocessable_entity
        end

        event = Event.find(reservation_params[:event_id])

        ticket_types = tickets_params.map do |ticket|
          TicketType.find(ticket[:ticket_type_id])
        end

        ticket_type_counts = ticket_types.tally

        unless ticket_types.all? { |ticket_type| ticket_type.event_id == event.id }
          return render json: {
            error: "Invalid ticket type for this event"
          }, status: :unprocessable_entity
        end

        reservation = nil

        ActiveRecord::Base.transaction do
          # Lock rows in a consistent order to reduce deadlock risk
          locked_ticket_types = TicketType
            .where(id: ticket_type_counts.keys.map(&:id))
            .order(:id)
            .lock("FOR UPDATE")
            .index_by(&:id)

          # Validate inventory after acquiring the locks
          ticket_type_counts.each do |ticket_type, requested_quantity|
            available = locked_ticket_types.fetch(ticket_type.id)

            if requested_quantity > available.quantity
              raise InsufficientInventoryError,
                    "Not enough tickets available for #{available.name}"
            end
          end

          total = ticket_type_counts.sum do |ticket_type, quantity|
            locked_ticket_types.fetch(ticket_type.id).price * quantity
          end

          reservation = Reservation.create!(
            user: current_user,
            event: event,
            status: "confirmed",
            total: total,
            confirmation_code: SecureRandom.hex(6)
          )

          tickets_params.each do |ticket|
            reservation.tickets.create!(
              ticket_type_id: ticket[:ticket_type_id],
              attendee_name: ticket[:attendee_name],
              attendee_email: ticket[:attendee_email],
              code: SecureRandom.hex(8)
            )
          end

          ticket_type_counts.each do |ticket_type, requested_quantity|
            locked_ticket_type = locked_ticket_types.fetch(ticket_type.id)

            locked_ticket_type.update!(
              quantity: locked_ticket_type.quantity - requested_quantity
            )
          end
        end

        if reservation.nil?
          return render json: {
            error: "Not enough tickets available"
          }, status: :unprocessable_entity
        end

        render json: ReservationSerializer.new(reservation).as_json,
              status: :created

      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages },
              status: :unprocessable_entity
      rescue InsufficientInventoryError => e
        render json: { error: e.message },
         status: :unprocessable_entity
      end

      private

      def reservation_params
        params.require(:reservation).permit(
          :event_id,
          tickets: [
            :ticket_type_id,
            :attendee_name,
            :attendee_email
          ]
        )
      end

      def tickets_params
        @tickets_params ||= reservation_params[:tickets]
      end
    end
  end
end