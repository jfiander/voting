module TermStyle
  def self.reset
    "\e[0m"
  end

  # Styles
  def self.bold
    "\e[1m"
  end

  def self.dim
    "\e[2m"
  end

  def self.underline
    "\e[4m"
  end

  def self.blink
    "\e[5m"
  end

  def self.invert
    "\e[7m"
  end

  def self.hidden
    "\e[8m"
  end

  # Colors
  def self.default
    "\e[39m"
  end

  def self.black
    "\e[30m"
  end

  def self.red
    "\e[31m"
  end

  def self.green
    "\e[32m"
  end

  def self.yellow
    "\e[33m"
  end

  def self.blue
    "\e[34m"
  end

  def self.magenta
    "\e[35m"
  end

  def self.cyan
    "\e[36m"
  end

  def self.gray
    "\e[37m"
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

    self.available
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
    define_method style do
      "#{self}#{TermStyle.send(style)}"
    end
  end
end

