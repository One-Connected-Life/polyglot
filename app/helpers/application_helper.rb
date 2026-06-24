module ApplicationHelper
  # Shared input styling — distinct bg, border, padding, dark variants (ux-primer:
  # "an input must read as an input"). Hints/placeholders muted vs entered text.
  def field_classes
    "w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-base sm:text-sm outline-none " \
      "focus:border-brand-indigo focus:ring-2 focus:ring-brand-indigo/20 " \
      "dark:border-gray-700 dark:bg-gray-900 dark:text-gray-100 " \
      "dark:placeholder-gray-500 dark:focus:border-brand-sky dark:focus:ring-brand-sky/20"
  end

  def primary_button_classes
    "w-full rounded-lg bg-brand-indigo px-4 py-2 text-sm font-medium text-white shadow-sm " \
      "hover:bg-brand-indigo/90 dark:bg-brand-indigo dark:text-white dark:hover:bg-brand-indigo/80"
  end

  # [name, code] pairs for language <select>s.
  def language_options
    Translation::LANGUAGES.map { |code, name| [name, code] }
  end
end
