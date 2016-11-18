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
end

class String
  def bright
    if self.match /\e\[3\dm/
      self.gsub("[3", "[9")
    else
      puts "Not a valid terminal color sequence."
      self
    end
  end

  def cancel
    if self.match /\e\[[1,2,4,5,7,8]m/
      self.gsub("[", "[2")
    else
      puts "Not a valid terminal style sequence."
      self
    end
  end
end

