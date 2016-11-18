module TermStyle
  # Global
  def self.reset
    self.style { 0 }
  end

  # Styles
  def self.bold
    self.style { 1 }
  end

  def self.dim
    self.style { 2 }
  end

  def self.underline
    self.style { 4 }
  end

  def self.blink
    self.style { 5 }
  end

  def self.invert
    self.style { 7 }
  end

  def self.hidden
    self.style { 8 }
  end

  # Colors
  def self.default
    self.color { 9 }
  end

  def self.black
    self.color { 0 }
  end

  def self.red
    self.color { 1 }
  end

  def self.green
    self.color { 2 }
  end

  def self.yellow
    self.color { 3 }
  end

  def self.blue
    self.color { 4 }
  end

  def self.magenta
    self.color { 5 }
  end

  def self.cyan
    self.color { 6 }
  end

  def self.gray
    self.color { 7 }
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
         colors: [
                   :default,
                   :black,
                   :red,
                   :green,
                   :yellow,
                   :blue,
                   :magenta,
                   :cyan,
                   :gray
                 ],
         styles: [
                   :bold,
                   :dim,
                   :underline,
                   :blink,
                   :invert,
                   :hidden
                 ]
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

