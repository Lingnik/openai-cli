#!/usr/bin/env ruby

require "optparse"
require "openai"
require "net/http"

def debug(message)
  puts "\e[31m#{message}\e[0m"
end

class OpenAIClient
  def initialize(api_key)
    @api_key = api_key
  end

  def prompt_openai(options = {})
    request = Net::HTTP::Post.new(
      URI("https://api.openai.com/v1/chat/completions"),
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{@api_key}"
    )
    request.body = body_for_options(options)

    if options.key?(:stream) && options[:stream]
      # Streaming prompts return in chunks.
      request_streaming(request, options[:json])
    else
      # JSON/Text prompts return immediately, after processing and network latency.
      request_non_streaming(request)
    end
  end

  private

  def request_streaming(request, stream_as_json=false)
    collected_chunks = []

    if stream_as_json == true
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
          while line = buffer.slice!(/.+\r?\n/)
            next if line.strip.empty?
            next unless line.start_with?("data: ")
            data = line[6..-1].strip
            next if data == "[DONE]"

            # Parse the data as JSON, add it as a chunk, print its content.
            parsed_chunk = JSON.parse(data)
            collected_chunks << parsed_chunk
            if stream_as_json == true
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
    if stream_as_json == true
      puts "]"
    end

    collected_chunks
  end

  def request_non_streaming(request)
    response = Net::HTTP.start(request.uri.host, request.uri.port, use_ssl: true) do |http|
      http.request(request)
    end
    response_json = JSON.parse(response.body)
    if response.is_a?(Net::HTTPSuccess)
      response_json
    else
      warn response_json
      raise StandardError, "Error"
    end
  end

  def body_for_options(options = {})
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


class OpenAICLI

  def self.main
    options = parse_options 

    # Instantiate the OpenAIClient module
    client = OpenAIClient.new(options[:api_key])
    options.delete(:api_key) # Keep it secret. Keep it safe.

    # Call the prompt_openai method
    #begin
    response = client.prompt_openai(options)

    if options[:stream]
      # The results have already been streamed, so do nothing.
      #puts response.map { |e| e["choices"][0]["delta"]&.fetch("content", "") }.reject(&:empty?).join
    elsif options[:json]
      puts JSON.pretty_generate(response)
    else
      puts response["choices"][0]["message"]["content"]
    end
    #rescue => e
    #  puts "Error: #{e.message}"
    #  puts e.backtrace if ENV["DEBUG"] == "true"
    #  exit(1)
    #end
  end

  private
  
  def self.parse_options 
    options = {
      :api_key => ENV["OPENAI_API_KEY"],
      :model => ENV["OPENAI_MODEL"] || "gpt-3.5-turbo",
      :max_tokens => 1000,
      :n => 1,
      :temperature => 0.5,
      :stream => false
    }

    parser = OptionParser.new do |opts|
      opts.banner = "Usage: openai [options]"

      opts.separator ""
      opts.separator "ChatGPT request parameters:"

      opts.on("-m", "--model MODEL", "Set the OpenAI model name (default: OPENAI_MODEL from env or gpt-3.5-turbo)") do |model|
        options[:model] = model
      end

      opts.on("-s", "--system-prompt PROMPT", "Set the system prompt") do |prompt|
        options[:system_prompt] = prompt
      end

      opts.on("-S", "--system-prompt-file FILE", "Set the system prompt based on the contents of FILENAME.") do |file|
        if opts.key?[:system_prompt]
          warn "WARNING: Both --system-prompt and --system-prompt-file were provided."
          exit(1)
        end
        options[:system_prompt] = File.read(file)
      end

      opts.on("-u", "--user-prompt PROMPT", "Set the user prompt") do |prompt|
        options[:user_prompt] = prompt
      end

      opts.on("-U", "--user-prompt-file FILE", "Set the user prompt based on the contents of FILENAME.") do |file|
        if opts.key?[:user_prompt]
          warn "WARNING: Both --user-prompt and --user-prompt-file were provided."
          exit(1)
        end
        options[:user_prompt] = File.read(file) 
      end

      opts.on("-t", "--max-tokens TOKENS", Integer, "Set the maximum number of tokens to generate (default: 1000)") do |tokens|
        options[:max_tokens] = tokens
      end

      opts.on("-n", "--n N", Integer, "Set the number of completions to generate (default: 1)") do |n|
        options[:n] = n
      end

      opts.on("--stop STOP", "Set the stop sequence") do |stop|
        options[:stop] = stop
      end

      opts.on("-p", "--temperature TEMPERATURE", Float, "Set the sampling temperature (default: 0.5)") do |temperature|
        options[:temperature] = temperature
      end

      opts.separator ""
      opts.separator "Specifying all paramters from a file"

      opts.on("-r", "--read-options FILE", "Read GPT parameters from a JSON file") do |file|
        json_options = JSON.parse(File.read(file), symbolize_names: true)
        options.merge!(json_options)
      end

      opts.on("-w", "--write-options FILE", "Save the GPT parameters to a JSON file") do |file|
        options_to_save = options.dup
        options_to_save.delete(:api_key)
        options_to_save.delete(:json)
        options_to_save.delete(:stream)
        File.write(file, JSON.pretty_generate(options_to_save))
        puts "Options saved to '#{file}'."
        exit
      end

      opts.separator ""
      opts.separator "General options:"

      opts.on("-k", "--api-key KEY", "Set the OpenAI API key (default: OPENAI_API_KEY from env or nil)") do |key|
        options[:api_key] = key
      end

      opts.on("-j", "--json", "Return the full raw response as JSON") do
        options[:json] = true
      end

      opts.on("-l", "--stream", "--live", "Stream the response in realtime.") do
        options[:stream] = true
      end

      opts.on("-h", "--help", "Prints this help") do
        puts opts
        exit
      end
    end

    parser.parse!

    missing_options = [:api_key, :system_prompt, :user_prompt].select { |opt| !options[opt] }

    # Check if required options are present
    if !missing_options.empty?
      err = "Missing required options: #{missing_options.join(', ')}"
      if $stdout.tty? && ENV['TERM'] != 'dumb'
        warn "\e[31m#{err}\e[0m"
      else
        warn err
      end
      puts ""
      puts parser.help
      exit(1)
    end

    options
  end

end

OpenAICLI.main


