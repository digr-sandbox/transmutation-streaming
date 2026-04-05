module Transmutation
  class RubyWorker
    attr_reader :worker_id

    def initialize(id)
      @worker_id = id
    end

    def transform(payload)
      return nil if payload.nil?
      puts "Transforming in Ruby: #{@worker_id}"
      payload.upcase
    rescue => e
      log_error(e)
    end

    private
    def log_error(err)
      warn "Error: #{err.message}"
    end
  end
end