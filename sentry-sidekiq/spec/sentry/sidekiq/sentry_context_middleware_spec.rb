require "spec_helper"

class TestWorker
  include Sidekiq::Worker

  def perform; end
end

RSpec.shared_context "sidekiq", shared_context: :metadata do
  let(:client) do
    Sidekiq::Client.new.tap do |client|
      client.middleware do |chain|
        chain.add Sentry::Sidekiq::SentryContextClientMiddleware
      end
    end
  end

  let(:random_empty_queue) do
    Sidekiq::Queue.new(rand(10_000)).tap do |queue|
      queue.clear
    end
  end
end

RSpec.describe Sentry::Sidekiq::SentryContextServerMiddleware do
  include_context "sidekiq"

  before { perform_basic_setup }

  after do
    Sidekiq.server_middleware do |chain|
      # Remove the middleware with testing argument and re-add the middleware
      # to restore the chain.
      chain.remove described_class
      chain.add described_class
    end
  end

  it "sets user to the current scope from the job" do
    user = { "id" => rand(10_000) }
    Sentry.set_user(user)

    Sidekiq.server_middleware do |chain|
      chain.add described_class, testing_only_callback: lambda { |scope|
        expect(scope.user).to eq(user)
      }
    end

    queue = random_empty_queue
    options = { fetch: Sidekiq::BasicFetch.new(queues: [queue.name]) }
    processor = Sidekiq::Processor.new(nil, options)

    client.push('queue' => queue.name, 'class' => TestWorker, 'args' => [])

    expect(queue.size).to be(1)
    processor.process_one
    expect(queue.size).to be(0)
  end
end

RSpec.describe Sentry::Sidekiq::SentryContextClientMiddleware do
  include_context "sidekiq"

  before { perform_basic_setup }

  it "does not user to the job if user is absence in the current scope" do
    queue = random_empty_queue
    client.push('queue' => queue.name, 'class' => TestWorker, 'args' => [])

    expect(queue.size).to be(1)
    expect(queue.first["sentry_user"]).to be_nil
  end

  it "sets user of the current scope to the job if present" do
    queue = random_empty_queue
    user = { "id" => rand(10_000) }
    Sentry.set_user(user)

    client.push('queue' => queue.name, 'class' => TestWorker, 'args' => [])

    expect(queue.size).to be(1)
    expect(queue.first["sentry_user"]).to eq(user)
  end
end
