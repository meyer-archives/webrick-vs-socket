#!/usr/bin/env ruby
# encoding: utf-8

=begin

    6 6 ____ __  _  ___  __ __ ____,
        ||_  ||  | //  ' ||_/  ||_ '
        ||   \\__/ \\__/ || \\ ||__,
       _  _  _ ____, ____  ____  ____  ___  __ __   9 9
        \ \\ / ||__' ||__) ||__)  ||  //  ' ||_/
         \/\/  ||__, ||__) || \, _||_ \\__/ || \\, o

=end

require "webrick"
require "optparse"
require "json"
require "yaml"
require "shellwords"

DAEMON_NICENAME = "Dex"
DAEMON_VERSION = "2.0.0"
PORT = 2345

# Splat ensures that the args are joinable
def poots(*p); STDERR.puts [*p].join("\n"); end
def __poots(*p); STDERR.puts [*p].join("\n").split("\n").map{|e| "  #{e}" }.join("\n"); end

# Pretty colours
class String
	def console_red;       colorise(self, "\e[31m"); end
	def console_green;     colorise(self, "\e[32m"); end
	def console_grey;      colorise(self, "\e[30m"); end
	def console_bold;      colorise(self, "\e[1m");  end
	def console_underline; colorise(self, "\e[4m");  end
	def colorise(text, color_code)  "#{color_code}#{text}\e[0m" end
	def markitdown
		# TODO: Use lookahead/lookbehind magic to match pairs
		self.gsub! %r{\*\*(\w|[^\s][^*]*?[^\s])\*\*}x, "<strong>\\1</strong>"
		self.gsub! %r{  \*(\w|[^\s][^*]*?[^\s])\*  }x,     "<em>\\1</em>"
		self.gsub! %r{   `(\w|[^\s][^`]*?[^\s])`   }x,   "<code>\\1</code>"
		self
	end
end

OptionParser.new do |opts|
	opts.banner = "Usage: #{File.basename __FILE__} [options]"

	options = {}

	# TODO: A more sensible default?
	options[:src] = nil
	opts.on("-s", "--src [PATH]", "Dexfile source path") {|p| options[:src] = p}

	options[:dest] = nil
	opts.on("-d", "--dest [PATH]", "Compiled dexfile destination path") {|p| options[:src] = p}

	options[:verbose] = false
	opts.on("-v", "--verbose", "Run verbosely") {|v| options[:verbose] = v}

	DEX_OPTIONS = options
end.parse!


abort "Dexfile source path is required. See '#{File.basename __FILE__} --help' for more" unless DEX_OPTIONS[:src]
# abort "Dexfile destination path is required. See '#{File.basename __FILE__} --help' for more" unless DEX_OPTIONS[:dest]

# Config method
def getLatestConfig(srcDir)
	filesByModule = { global: [] }
	modulesByHost = { global: {}, utilities: {} }
	metadataByModule = {}
	contentsByFile = {}

	Dir.chdir File.realpath File.expand_path(srcDir)

	Dir.glob("*/{*,*/*}.{css,sass,scss,js,coffee}").reject do |f|
		!File.file?(f)
	end.each do |modPath|
		mod, slash, filename = modPath.rpartition("/")
		basename, dot, ext = filename.rpartition(".")
		parts = modPath.split("/")

		filesByModule[mod] ||= { css: [], js: [] }

		# Exclude host-wide files (like "global/setup.js")
		if parts.size > 2
			modulesByHost[parts[0]] ||= []
			modulesByHost[parts[0]] |= [mod]
			metadataByModule[mod] = {
				"Author" => nil,
				"Title" => "#{parts[1]}",
				"Category" => "#{parts[0] }",
				"Description" => nil,
				"URL" => nil
			}

			info_yaml = File.join(mod, "info.yaml")
			if File.exists? info_yaml
				__poots "Loading '#{info_yaml}'"
				(YAML::load_file(info_yaml) || {}).each do |k, v|
					case k
					when "Title", "Category" then next
					when String
						metadataByModule[mod][k] = v.markitdown
					else
						metadataByModule[mod][k] = v
					end
				end
			end
		end

		contents = "/* Error: #{modPath} */"
		action = "Compiled"

		coffee = `which coffee`.strip
		sass = `which sass`.strip

		case ext
		when "coffee"
			unless coffee === ""
				contents = `cat #{Shellwords.escape modPath} | #{coffee} -c -s`.strip
			else
				contents = "/* coffeescript is not installed */"
			end
		when "scss", "sass"
			unless sass === ""
				contents = `#{sass} #{Shellwords.escape modPath}`.strip
			else
				contents = "/* sass gem is not installed */"
			end
		else
			contents = IO.read(modPath)
			action = "Copied"
		end

		poots [
			"#{Time.now.strftime "%H:%M:%S"}".console_bold,
			action,
			modPath
		].join(" ")

		case ext
		when "js", "coffee"
			filesByModule[mod][:js].push modPath
			contents = [
				"console.groupCollapsed(\"#{modPath}\");",
				contents,
				"console.groupEnd();"
			].join("\n\n")
		when "css", "sass", "scss"
			filesByModule[mod][:css].push modPath
			contents = [
				"/* @start #{modPath} */",
				contents,
				"/* @end #{modPath} */"
			].join("\n\n")
		end

		contentsByFile[modPath] = contents
	end

	{
		:metadata => metadataByModule,
		:modulesByHost => modulesByHost,
		:filesByModule => filesByModule,
		:contentsByFile => contentsByFile
	}
end

DexServer = Class.new(WEBrick::HTTPServlet::AbstractServlet) do
	def do_GET (request, response)
		case request.path
		when "/getdata"
			response.content_type = "utf8"
			response.body = getLatestConfig(DEX_OPTIONS[:src]).to_json
		else
			response.content_type = "txt"
			response.body = "No such method"
		end
	end
end

poots "#{DAEMON_NICENAME} #{DAEMON_VERSION}".console_green
poots "Serving from '#{DEX_OPTIONS[:src].to_s}' on port #{PORT}"
poots "==========".console_grey

server = WEBrick::HTTPServer.new :Port => PORT, :DocumentRoot => DEX_OPTIONS[:src]
server.mount "/", DexServer

# Show a nice message on exit
%w(INT TERM).each{|s| trap(s){server.shutdown; poots "\ntake care out there \u{1f44b}"; abort}}

server.start