#!/usr/bin/env ruby
# openai.rb <args>
require "optparse"
require "thor"
require_relative "lib/api/chat"
require_relative "lib/api/transcription"
require_relative "lib/thor_option_monkey_patch"

def debug(msg)
  warn msg
end

module OpenAI
  class CLI < Thor
    class_option :api_key, :aliases => "-a", type: :string, banner: "your_api_key", desc: 'Set the OpenAI API key (if unset, env OPENAI_API_KEY)'
    class_option :json, :aliases => "-j", type: :boolean, default: false, desc: 'Return the full raw response as JSON'

    class_option :write, :aliases => "-w", type: :string, banner: "openai.json", desc: 'Save parameters to a JSON file'
    class_option :read, :aliases => "-r", type: :string, banner: "openai.json", desc: 'Read parameters from a JSON file'

    desc 'chat', 'Interact with OpenAI GPT via the command line'
    method_option :model, :required => true, :aliases => "-m", type: :string, banner: "gpt-4", default: ENV.fetch("OPENAI_MODEL", "gpt-3.5-turbo"), desc: "Set the OpenAI model name (default: env OPENAI_MODEL || gpt-3.5-turbo)"
    method_option :system, :required => true, :aliases => "-s", type: :string, banner: "\"prompt\"", desc: 'Set the system prompt'
    method_option :user, :required => true, :aliases => "-u", type: :string, banner: "\"prompt\"", desc: 'Set the user prompt'
    method_option :max_tokens, :aliases => "-t", type: :numeric, banner: "1000", default: 1000, desc: 'Set the maximum number of tokens to generate (default: 1000)'
    method_option :num_completions, :aliases => "-n", type: :numeric, banner: "1", default: 1, desc: 'Set the number of completions to generate (default: 1)'
    method_option :temperature, :aliases => "-p", type: :numeric, in: 0.0..2.0, banner: "0.5", default: 0.5, desc: 'Set the sampling temperature; lower=deterministic/higher=random (default: 0.5)'
    method_option :stop, :aliases => "-q", type: :array, repeatable: true, max: 4, banner: "\"###STOP###\"", desc: "Set up to four stop sequence(s) (default: none)\n\nChat CLI Options:"
    method_option :system_is_file, :aliases => "-S", type: :boolean, desc: "Treat --system as a filename; use its contents as the system prompt"
    method_option :user_is_file, :aliases => "-U", type: :boolean, desc: 'Treat --user as a filename; use its contents as the user prompt'
    method_option :stream, :aliases => "-l", type: :boolean, default: false, desc: "Stream the response in real-time\n\nGlobal Options:"
    def chat
      write_option = options[:write]
      chat_options = options.dup
      
      # If -r/--read was provided, merge options in from the specified file.
      chat_options.merge!(JSON.parse(File.read(options[:read]))) if options[:read]

      # If -S or -U were provided, read the system/user prompts from the specified file/s.
      chat_options[:system_prompt] = options[:system_is_file] ? File.read(chat_options[:system]) : chat_options[:system]
      chat_options[:user_prompt] = options[:user_is_file] ? File.read(chat_options[:user]) : chat_options[:user]

      # If -w was provided, marshal all options to a file and exit. Skip sensitive options.
      if options[:write]
        chat_options.delete(:api_key)
        chat_options.delete(:write)
        json_opts = JSON.pretty_generate(chat_options)
        File.write(write_option, json_opts)
        puts "Successfully wrote options to file \"#{write_option}\"."
        exit(0)
      end

      client = API::ChatClient.new(chat_options)
      response = client.request

      if chat_options[:stream]
        # The results have already been streamed, so do nothing.
        # puts response.map { |e| e["choices"][0]["delta"]&.fetch("content", "") }.reject(&:empty?).join
      elsif chat_options[:json]
        puts JSON.pretty_generate(response)
      else
        puts response["choices"][0]["message"]["content"]
      end
    end

    desc 'transcribe', 'Interact with OpenAI Whisper via the command line'
    method_option :model, :aliases => "-m", type: :string, :required => true, banner: "whisper-1", default: ENV.fetch("OPENAI_TRANSCRIBE_MODEL", "whisper-1"), desc: "Set the OpenAI model name (default: env OPENAI_MODEL || whisper-1)"
    method_option :file, :aliases => "-f", type: :string, :required => true, banner: "file", desc: "The audio file to transcribe (mp3, mp4, mpeg, mpga, m4a, wav, or webm)"
    method_option :prompt, :aliases => "-p", type: :string, desc: "Optional text to guide the model's style or continue a previous audio segment"
    method_option :prompt_is_file, :aliases => "-P", type: :boolean, desc: "Treat --prompt as a filename; use its contents as the prompt"
    method_option :output, :aliases => "-o", type: :string, desc: "The format of the transcript output (json, text, srt, verbose_json, or vtt)"
    method_option :temperature, :aliases => "-p", type: :numeric, in: 0.0..1.0, banner: "0.0", default: 0.0, desc: 'Set the sampling temperature; lower=deterministic/higher=random (default: 0.0=dynamic)'
    method_option :language, :aliases => "-l", type: :string, desc: "The language of the input audio in ISO-639-1 format"
    def transcribe
      write_option = options[:write]
      transcribe_options = options.dup

      # If -r/--read was provided, merge options in from the specified file.
      transcribe_options.merge!(JSON.parse(File.read(options[:read]))) if options[:read]

      transcribe_options[:prompt] = options[:prompt_is_file] ? File.read(transcribe_options[:prompt]) : transcribe_options[:prompt]

      # If -w was provided, marshal all options to a file and exit. Skip sensitive options.
      if options[:write]
        transcribe_options.delete(:api_key)
        transcribe_options.delete(:write)
        json_opts = JSON.pretty_generate(transcribe_options)
        File.write(write_option, json_opts)
        puts "Successfully wrote options to file \"#{write_option}\"."
        exit(0)
      end

      client = API::TranscribeClient.new(options)
      response = client.request

      if options[:json]
        puts JSON.pretty_generate(response)
      else
        puts JSON.pretty_generate(response)
        puts response["choices"][0]["message"]["content"]
      end
    end

    def self.exit_on_failure?
      true
    end

  end

end

o = OpenAI::CLI
o.start(ARGV)