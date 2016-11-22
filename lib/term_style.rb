module TermStyle
  @term_style_config = {
    style: {
           reset: 0,
            bold: 1,
             dim: 2,
       underline: 4,
           blink: 5,
          invert: 7,
          hidden: 8
    },
    color: {
      default: 9,
        black: 0,
          red: 1,
        green: 2,
       yellow: 3,
         blue: 4,
      magenta: 5,
         cyan: 6,
         gray: 7
    }
  }

  @term_style_config.each do |type, tag_info|
    tag_info.each do |tag_name, tag_num|
      define_method tag_name do
        self.send(type) { tag_num }
      end
    end
  end

  # Helpers
  def self.available(mode = nil)
    available_methods = {
        control:   :reset,
      modifiers: [
                   :bright,
                   :regular,
                   :cancel
                 ],
         colors: @term_style_config[:color].keys,
         styles: @term_style_config[:style].keys.reject { |s| s == :reset }
    }

    if mode == :flat
      [available_methods[:control], available_methods[:colors], available_methods[:styles]].flatten
    else
      available_methods
    end
  end

  def self.demo
    puts "COLORS:"
    self.available[:colors].each do |color|
      padding = " " * 3
      print "#{self.send(color)}#{color}#{self.reset} #{padding}"
    end

    puts "\n\nSTYLES:"
    self.available[:styles].each do |style|
      padding = " " * (self.available[:colors].map(&:length).max + 1)
      print "#{self.send(style)}#{style}#{self.reset} #{padding}"
    end

    puts "\n\nCOMBINATIONS:"
    self.available[:colors].each do |color|
      padding = " " * (self.available[:colors].map(&:length).max - color.length)
      self.available[:styles].each do |style|
        print "#{self.send(color)}#{self.send(style)}#{style} #{color}#{self.reset} #{padding}"
      end
      print "\n"
    end

    puts "\n\nEXAMPLE:"
    puts "puts \"Green\".style(:green) + \"bold white\".bold.red(:append) + \"red underlined\".bold.cancel.underline + \"blue invert\".blue.invert.reset(:append)"
    puts "Green".style(:green) + "bold white".bold.red(:append) + "red underlined".bold.cancel.underline + "blue".blue.invert.reset(:append)

    self.available
  end

  private
  def self.escape(body, prefix = nil)
    "\e[#{prefix}#{body}m"
  end

  def self.style(&block)
    self.escape(yield)
  end

  def self.color(&block)
    self.escape(yield, 3)
  end
end

class String
  def bright
    # Convert valid color sequences to bright version
    if self.match /\e\[3\dm/
      self.gsub("[3", "[9")
    else
      puts "Not a valid regular terminal color sequence."
      self
    end
  end

  def regular
    # Convert valid color sequences to bright version
    if self.match /\e\[9\dm/
      self.gsub("[9", "[3")
    else
      puts "Not a valid bright terminal color sequence."
      self
    end
  end

  def cancel
    # Cancel valid style sequences
    if self.match /\e\[[1,2,4,5,7,8]m/
      self.gsub(/\[[1,2,4,5,7,8]/, "[2")
    else
      puts "Not a valid terminal style sequence."
      self
    end
  end

  TermStyle.available(:flat).each do |style|
    define_method style do |pos = :prepend|
      if pos == :append
        "#{self}#{TermStyle.send(style)}"
      else
        "#{TermStyle.send(style)}#{self}"
      end
    end
  end

  def style(*styles)
    str = self
    styles.each do |s|
      str = if TermStyle.available[:modifiers].include? s
        str.send(s)
      else
        "#{TermStyle.send(s)}#{str}#{TermStyle.reset}"
      end
    end
    str
  end
end

