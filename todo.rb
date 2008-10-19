# This is code to be added to NekoSexpProcessor

=begin
  def process_str(exp)
    return exp.shift.dump
  end

  def process_lasgn(exp)
    s = "var #{exp.shift}"
    s += " = #{process exp.shift}" unless exp.empty?
    s
  end

  def process_gasgn(exp)
    s = "#{exp.shift.to_s.gsub('$', '')}"
    s += " = #{process exp.shift}" unless exp.empty?
    s
  end

  def process_gvar(exp)
    return exp.shift.to_s.gsub('$', '')
  end

  def process_array(exp)
    "$array(#{process_arglist(exp)})"
  end

  def process_const(exp)
    exp.shift.to_s
  end

  def process_module(exp)
    util_module_or_class(exp)
  end

  def process_class(exp)
    util_module_or_class(exp, true)
  end

  private
  def util_module_or_class(exp, is_class = false)
    result = []

    name = exp.shift
    name = process name if Sexp === name

    result << name
    result << "="
    result << "$new"

    if is_class then
      superk = process(exp.shift)
      if superk then
        result << "(#{superk});"
      else
        result << "(null);"
      end
    else
      result << "(null);"
    end

    result << "\n"

    @klasses.push name

    body = []
    begin
      code = process(exp.shift).chomp
      body << code unless code.nil? or code.empty?
    end until exp.empty?

    unless body.empty? then
      body = indent(body.join("\n\n") + "\n")
    else
      body = ""
    end
    result << body

    @klasses.pop

    result.join
  end

  def process_ivar(exp)
    return "this.#{exp.shift.to_s.gsub("@", '')}"
  end

  def process_iasgn(exp)
    lhs = exp.shift.to_s.gsub("@", '')
    if exp.empty? then # part of an masgn
      lhs.to_s
    else
      "this.#{lhs} = #{process exp.shift}"
    end
  end

  def process_self(exp)
    "this"
  end
=end

primitives =<<-SCRIPT
  class Object
    def new(*args)
      self.initialize(args)
    end
  end

  class Foo
    def hello
      puts "hello"
    end
  end

  Foo.new.hello
SCRIPT

inherit =<<-SCRIPT
  class Foo
    def hello
      puts "hello!"
    end
  end

  class Bar < Foo
    def goodbye
      puts "bye!"
    end
  end

  Bar.new.hello()
SCRIPT

classes =<<-SCRIPT
  class Time
    def new
      @now = date_now()
      return self
    end

    def to_i
      return @now
    end
  end

  start_time = Time.new
  puts start_time.to_i
SCRIPT

globals =<<-SCRIPT
  class Foo
    def hello(name)
      $x = 100
      puts "Hello World!"
      puts $x
    end
  end
SCRIPT
