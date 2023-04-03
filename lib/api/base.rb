module OpenAI
  module API
    class Base
      def initialize(options)
        raise NotImplementedError, "Subclasses must implement `initialize`."
      end

      def request
        raise NotImplementedError, "Subclasses must implement `request`."
      end
    end
  end
end
