require 'rubygems'
require 'parse_tree'
require 'sexp_processor'
require 'unified_ruby'

require 'pp'

code =<<-SCRIPT
  class Fib
    def fib(n)
      if n <= 1
        return 1
      else 
        return fib(n-1) + fib(n-2)
      end
    end
  end

  puts Fib.fib(20)
SCRIPT

code2 =<<-SCRIPT
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

code3 =<<-SCRIPT
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

=begin
class Foo
  def hello(name)
    $x = 100
    puts "Hello World!"
    puts $x
  end
end
=end

class Neko < SexpProcessor
  include UnifiedRuby

  XLATE_MAP = {
    :puts => '$print'
  }

  def initialize
    super
    @klasses = []
    @indent = "  "

    self.auto_shift_type = true
    self.strict = true
    self.expected = String
  end

  def translate_function(fname)
    XLATE_MAP[fname] || fname
  end

  def process(exp)
    exp = Sexp.from_array(exp) if Array === exp unless Sexp === exp
    super exp
  end

  def process_args(exp)
    args = []
    until exp.empty?
      arg = exp.shift
      case arg
      when Symbol then
        args << arg.to_s
      end
    end
    return "(#{args.join ','})"
  end

  def process_scope(exp)
    exp.empty? ? "" : process(exp.shift)
  end

  def process_call(exp)
    receiver_node_type = exp.first.nil? ? nil : exp.first.first
    receiver = process exp.shift

    #receiver = "(#{receiver})" if
    #  Ruby2Ruby::ASSIGN_NODES.include? receiver_node_type

    name = exp.shift
    args_exp = exp.shift rescue nil
    if args_exp && args_exp.first == :array # FIX
      args = "#{process(args_exp)[1..-2]}"
    else
      args = process args_exp
      args = nil if args.empty?
    end

    case name
    when :<=>, :==, :<, :>, :<=, :>=, :-, :+, :*, :/, :%, :<<, :>>, :** then
      "(#{receiver} #{name} #{args})"
    when :[] then
      "#{receiver}[#{args}]"
    when :"-@" then
      "-#{receiver}"
    when :"+@" then
      "+#{receiver}"
    else
      unless receiver.nil? then
        "#{receiver}.#{name}(#{args})"
      else
        "#{translate_function(name)}(#{args})"
      end
    end
  end

  def process_str(exp)
    return exp.shift.dump
  end

  def process_if(exp)
    c = process exp.shift
    t = process exp.shift
    f = process exp.shift

    c = "(#{c.chomp})" if c =~ /\n/

    r = "if #{c} {\n#{t}}\n"
    r << "else {\n#{f}\n" if f
    r << "}"
    r
  end

  def process_arglist(exp)
    code = []
    until exp.empty? do
      code << process(exp.shift)
    end
    code.join ', '
  end

  def process_block(exp)
    result = []

    exp << nil if exp.empty?
    until exp.empty? do
      code = exp.shift
      if code.nil? or code.first == :nil then
        result << "# do nothing"
      else
        result << process(code)
      end
    end

    result = result.join "\n"

    result = case self.context[1]
             when nil, :scope, :if, :iter, :resbody, :when, :while then
               result + "\n"
             else
               "(#{result})"
             end

    return result
  end

  def process_lvar(exp)
    exp.shift.to_s
  end

  def process_lit(exp)
    exp.shift.inspect
  end

  def process_return(exp)
    "return #{process(exp.shift)}"
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

  def process_defn(exp)
    type1 = exp[1].first
    #type2 = exp[2] rescue nil #.first 

    result = []

    case type1
        when :scope, :args then
        name = exp.shift.to_s
        name.gsub!('?', '_q')
        args = process(exp.shift)
        body = process(exp.shift)
        parent = @klasses.join('.')
        unless @klasses.empty?
          result << parent
          result << "."
        end
        result << name
        return "#{result.join} = function#{args} {\n#{indent(body)}\n}"
      else
        raise "Unknown defn type: #{type1} for #{exp.inspect}"
    end
  end

  def util_module_or_class(exp, is_class = false)
    result = []

    name = exp.shift
    name = process name if Sexp === name

    result << name
    result << "="
    result << "$new"

    if is_class then
      superk = process(exp.shift)
      if superk == "Object" then
        result << "(null);"
      else
        result << "(#{superk});"
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

  def indent(s)
    s.to_s.split(/\n/).map{|line| @indent + line}.join("\n")
  end
end

sexp = ParseTree.translate(code)
puts "SEXP"
pp sexp
puts Neko.new.process(sexp)
