#api/chat.rb

require_relative "base"
require "net/http"
require "json"

module OpenAI
  module API
    class ChatClient < Base

      def initialize(options)
        @options = options
      end

      def request
        request = Net::HTTP::Post.new(
          URI("https://api.openai.com/v1/chat/completions"),
          'Content-Type' => 'application/json',
          'Authorization' => "Bearer #{@options[:api_key] || ENV.fetch("OPENAI_API_KEY", nil)}"
        )
        request.body = ChatClient.body_for_options(@options)

        if @options.key?(:stream) && @options[:stream]
          # Streaming prompts return in chunks.
          ChatClient.request_streaming(request, @options[:json])
        else
          # JSON/Text prompts return immediately, after processing and network latency.
          ChatClient.request_non_streaming(request)
        end
      end

      private

      def self.request_streaming(request, stream_as_json=false)
        collected_chunks = []

        if stream_as_json
          puts "["
        end
        first = true
        Net::HTTP.start(request.uri.host, request.uri.port, use_ssl: true) do |http|
          http.request(request) do |response|

            if !response.content_type == "text/event-stream"
              warn JSON.parse(response.body)
              raise "Unexpected response content type, expected text/event-stream: #{response.content_type}"
            end

            buffer = ""
            response.read_body do |chunk|
              buffer += chunk
              while (line = buffer.slice!(/.+\r?\n/))
                next if line.strip.empty?
                next unless line.start_with?("data: ")
                data = line[6..-1].strip
                next if data == "[DONE]"

                # Parse the data as JSON, add it as a chunk, print its content.
                parsed_chunk = JSON.parse(data)
                collected_chunks << parsed_chunk
                if stream_as_json
                  if first
                    first = false
                  else
                    print ",\n"
                  end
                  print "  #{parsed_chunk}"
                  $stdout.flush
                else
                  if parsed_chunk["choices"] &&
                    parsed_chunk["choices"][0] &&
                    parsed_chunk["choices"][0]["delta"] &&
                    parsed_chunk["choices"][0]["delta"]["content"]
                    print parsed_chunk["choices"][0]["delta"]["content"]
                    $stdout.flush
                  end
                end
              end
            end
            puts ""
          end
        end
        if stream_as_json
          puts "]"
        end

        collected_chunks
      end

      def self.request_non_streaming(request)
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

      def self.body_for_options(options = {})
        {
          "model": options[:model],
          "messages": [
            {
              "role": "system",
              "content": options[:system_prompt]
            },
            {
              "role": "user",
              "content": options[:user_prompt]
            }
          ],
          "max_tokens": options[:max_tokens],
          "n": options[:n],
          "stop": options[:stop],
          "temperature": options[:temperature],
          "stream": options[:stream]
        }.to_json
      end

    end
  end
end