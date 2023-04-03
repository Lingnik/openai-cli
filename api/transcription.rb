require_relative "base"
require "net/http"
require "json"

module OpenAI
  module API
    class TranscribeClient < Base

      def initialize(options)
        @options = options
      end

      def request
        request = Net::HTTP::Post.new(
          URI("https://api.openai.com/v1/audio/transcriptions"),
          'Content-Type' => 'application/json',
          'Authorization' => "Bearer #{@options[:api_key] || ENV.fetch("OPENAI_API_KEY", nil)}"
        )
        opt_body = TranscribeClient.body_for_options(@options)
        request.set_form(opt_body.merge({'file': File.open(@options[:file])}), 'multipart/form-data')

        response = Net::HTTP.start(request.uri.host, request.uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        if response && response.is_a?(Net::HTTPSuccess)
          JSON.parse(response.body)
        else
          warn response ? response.body : "Response was nil."
          raise StandardError, "Error"
        end
      end

      private

      def self.body_for_options(options = {})
        {
          "model": options[:model],
          "prompt": options[:prompt],
          "response_format": options[:output],
          "temperature": options[:temperature],
          "language": options[:language]
        }.to_json
      end
    end
  end
end