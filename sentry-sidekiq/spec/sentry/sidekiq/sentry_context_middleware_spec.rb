require "spec_helper"

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

  it "sets user to the current scope from the job" do
    perform_basic_setup do |config|
      config.traces_sample_rate = 1.0
    end

    user = { "id" => rand(10_000) }
    Sentry.set_user(user)

    queue = random_empty_queue
    options = { fetch: Sidekiq::BasicFetch.new(queues: [queue.name]) }
    processor = Sidekiq::Processor.new(nil, options)

    client.push('queue' => queue.name, 'class' => HappyWorker, 'args' => [])

    expect(queue.size).to be(1)
    processor.process_one
    expect(queue.size).to be(0)

    event = Sentry.get_current_client.transport.events.first
    expect(event).not_to be_nil
    expect(event.user).to eq(user)
  end

  it "sets user to the current scope from the job even if worker raises an exception" do
    perform_basic_setup do |config|
      config.traces_sample_rate = 1.0
    end

    user = { "id" => rand(10_000) }
    Sentry.set_user(user)

    queue = random_empty_queue
    options = { fetch: Sidekiq::BasicFetch.new(queues: [queue.name]) }
    processor = Sidekiq::Processor.new(nil, options)

    client.push('queue' => queue.name, 'class' => SadWorker, 'args' => [])

    expect(queue.size).to be(1)
    begin
      processor.process_one
    rescue RuntimeError
      # do nothing
    end
    expect(queue.size).to be(1)

    event = Sentry.get_current_client.transport.events.first
    expect(event).not_to be_nil
    expect(event.user).to eq(user)
  end
end

RSpec.describe Sentry::Sidekiq::SentryContextClientMiddleware do
  include_context "sidekiq"

  before { perform_basic_setup }

  it "does not user to the job if user is absence in the current scope" do
    queue = random_empty_queue
    client.push('queue' => queue.name, 'class' => HappyWorker, 'args' => [])

    expect(queue.size).to be(1)
    expect(queue.first["sentry_user"]).to be_nil
  end

  it "sets user of the current scope to the job if present" do
    queue = random_empty_queue
    user = { "id" => rand(10_000) }
    Sentry.set_user(user)

    client.push('queue' => queue.name, 'class' => HappyWorker, 'args' => [])

    expect(queue.size).to be(1)
    expect(queue.first["sentry_user"]).to eq(user)
  end
end
