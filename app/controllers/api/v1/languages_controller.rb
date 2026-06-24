module Api
  module V1
    # GET /api/v1/languages — the app's language registry (Translation::LANGUAGES),
    # as an ordered array of { code, name }. Lets the client build pickers without
    # hardcoding the list.
    class LanguagesController < BaseController
      def index
        render json: {
          languages: Translation::LANGUAGES.map { |code, name| { code: code, name: name } },
          non_latin: Translation::NON_LATIN,
        }
      end
    end
  end
end
