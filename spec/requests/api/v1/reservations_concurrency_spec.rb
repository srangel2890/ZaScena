
require "rails_helper"

RSpec.describe "Concurrent reservations", type: :request do
  self.use_transactional_tests = false

  let!(:user) do
    User.create!(
      email: "concurrency-test@example.com",
      name: "Concurrency Tester",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  let!(:venue) do
    Venue.create!(name: "Concurrency Test Venue")
  end

  let!(:event) do
    Event.create!(
      name: "Concurrency Test Event",
      starts_at: 1.month.from_now,
      user: user,
      venue: venue
    )
  end

  let!(:ticket_type) do
    TicketType.create!(
      name: "VIP",
      price: 1200,
      quantity: 1,
      event: event
    )
  end

  after do
    Ticket.where(ticket_type_id: ticket_type.id).delete_all
    Reservation.where(event_id: event.id).delete_all
    User.find_by(email: 'concurrency-test@example.com').destroy
    ticket_type.destroy!
    event.destroy!
    venue.destroy!
  end

  it "does not oversell the last available ticket" do
    headers = {
      "Authorization" => "Bearer #{user.get_token}"
    }

    responses = []
    mutex = Mutex.new

    threads = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          session = ActionDispatch::Integration::Session.new(
            Rails.application
          )

          session.host! "www.example.com"
          puts "Thread #{Thread.current.object_id}"
          puts "Route exists: #{Rails.application.routes.recognize_path('/api/v1/reservations', method: :post)}"  
          session.post(
            "/api/v1/reservations",
            params: {
              reservation: {
                event_id: event.id,
                tickets: [
                  {
                    ticket_type_id: ticket_type.id,
                    attendee_name: "Test Attendee",
                    attendee_email: "test@example.com"
                  }
                ]
              }
            },
            headers: headers
          )

          mutex.synchronize do
            responses << session.response.status
          end
        end
      end
    end

    threads.each(&:value)

    expect(responses.sort).to eq([201, 422])
    expect(Reservation.where(event_id: event.id).count).to eq(1)
    expect(Ticket.where(ticket_type_id: ticket_type.id).count).to eq(1)
    expect(ticket_type.reload.quantity).to eq(0)
  end
end