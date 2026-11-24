class Reservation < ApplicationRecord
  belongs_to :user
  belongs_to :event

  has_many :tickets

  validates :status, presence: true
  validates :confirmation_code, presence: true, uniqueness: true

  scope :by_user, ->(user) { where(user_id: user.id) }
  
  def self.create_from_hash(reservation_params, tickets_params, user)
    event = Event.find(reservation_params[:event_id])
        ticket_types = tickets_params.map do |ticket|
          TicketType.find(ticket[:ticket_type_id])
        end

    ticket_type_counts = ticket_types.tally

    unless ticket_types.all? { |ticket_type| ticket_type.event_id == event.id }
      raise InvalidTicketTypeError,
          "Ticket type does no belong to event"
    end
    reservation = nil
    total = 0
    ActiveRecord::Base.transaction do
      locked_ticket_types = TicketType
        .where(id: ticket_type_counts.keys.map(&:id))
        .order(:id)
        .lock("FOR UPDATE")
        .index_by(&:id)

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
        user: user,
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
        locked_ticket_type.update!( quantity: locked_ticket_type.quantity - requested_quantity)
      end
    end
    reservation
  end
end