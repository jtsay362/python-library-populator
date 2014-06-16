require 'json'
require 'nokogiri'

class PythonLibraryPopulator
  def initialize(dir_path, output_path)
    @dir_path = dir_path
    @output_path = output_path
    @first_document = true
    @num_names_found = 0
  end

  def debug(msg)
    
  end
  
  def populate
    puts "Populating from '#{@dir_path}' to #{@output_path}' ..."

    first_document = true

    File.open(@output_path, 'w') do |out|
      out.write <<-eos
{
  "metadata" : {
    "mapping" : {
      "_all" : {
        "enabled" : false
      },
      "properties" : {
        "name" : {
          "type" : "string",
          "index" : "not_analyzed"
        },
        "kind" : {
          "index" : "no"
        },
        "params" : {
          "index" : "no"
        },
        "path" : {
          "index" : "no"
        }
      }
    }
  },
  "updates" : [
      eos

      Dir["#{@dir_path}/library/*.html"].each do |file_path|

        simple_filename = File.basename(file_path)

        puts "Opening file '#{file_path}' ..."

        File.open(file_path) do |f|
          doc = Nokogiri::HTML(f)
          find_names(doc, simple_filename, out)
        end
      end

      out.write("\n  ]\n}")

      puts "Found #{@num_names_found} names."
    end
  end

  def find_names(doc, simple_filename, out)
    doc.css('dl.function, dl.method, dl.class, dl.classmethod, dl.exception').each do |dl|
      begin
        kind = dl.attr('class')
        dt = dl.css('dt')[0]

        #debug "Found element #{dt.to_s}"

        full_name = dt.attr('id')
        class_name = dt.css('tt.descclassname')[0].text() rescue ''

        if class_name.end_with?('.')
          class_name = class_name.slice(0, class_name.length - 1)
        end

        simple_name = dt.css('tt.descname')[0].text()


        params = dt.css('em').collect do |em|
          em.text().strip()
        end


        summary = dl.css('dd').text()
        relative_path = simple_filename + (dl.css('a.headerlink')[0].attr('href') rescue '')

        puts "Full name = '#{full_name}'"
        debug "Class name = '#{class_name}'"
        puts "Parameters = (#{params.join(',')})"
        debug "Simple name = '#{simple_name}'"
        debug "Summary = '#{summary}'"
        debug "Path = '#{relative_path}'"

        output_doc = {
            name: full_name,
            simpleName: simple_name,
            params: params,
            kind: kind,
            path: relative_path,
            summary: summary
        }

        if @first_document
          @first_document = false
        else
          out.write(",\n")
        end

        out.write(output_doc.to_json)

        @num_names_found += 1
      rescue => e
        puts "Exception: '#{e.message}'"
        puts e.backtrace
        puts "Ignoring function element #{dl.to_s}"
      end
    end
  end
end

output_filename = 'python-doc.json'

if ARGV.length > 1
  output_filename = ARGV[1]
end

PythonLibraryPopulator.new(ARGV[0], output_filename).populate