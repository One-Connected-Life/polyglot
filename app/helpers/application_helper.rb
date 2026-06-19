module ApplicationHelper
  # Shared input styling — distinct bg, border, padding, dark variants (ux-primer:
  # "an input must read as an input"). Hints/placeholders muted vs entered text.
  def field_classes
    "w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm outline-none " \
      "focus:border-gray-900 dark:border-gray-700 dark:bg-gray-900 dark:text-gray-100 " \
      "dark:placeholder-gray-500 dark:focus:border-gray-300"
  end

  def primary_button_classes
    "w-full rounded-lg bg-gray-900 px-4 py-2 text-sm font-medium text-white hover:bg-gray-800 " \
      "dark:bg-gray-100 dark:text-gray-900 dark:hover:bg-white"
  end

  # [name, code] pairs for language <select>s.
  def language_options
    Translation::LANGUAGES.map { |code, name| [name, code] }
  end
end
