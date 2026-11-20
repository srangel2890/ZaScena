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

        reservation = Reservation.create_from_hash(reservation_params, tickets_params, current_user)

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
      rescue InvalidTicketTypeError => e
        render json: {
            error: "Invalid ticket type for this event"
          }, status: :unprocessable_entity
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