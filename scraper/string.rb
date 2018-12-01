class String
  def is_i?
    /\A[-+]?\d+\z/ === self
  end

  def string_between_markers marker1, marker2
    self[/#{Regexp.escape(marker1)}(.*?)#{Regexp.escape(marker2)}/m, 1]
  end

  def titleize(exclude = [])
    split(/(\W)/).map do |word|
      exclude.map(&:downcase).include?(word.downcase) ? word : word.capitalize
    end.join
  end

  def underscore
    self.gsub(/::/, '/').
    gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
    gsub(/([a-z\d])([A-Z])/,'\1_\2').
    tr("-", "_").
    downcase
  end
end
