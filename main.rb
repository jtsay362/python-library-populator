require 'json'
require 'nokogiri'
require 'cgi'

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
    "settings" : {
      "analysis": {
        "char_filter" : {
          "no_special" : {
            "type" : "mapping",
            "mappings" : [".=>", "*=>", "(=>", ")=>", "_=>"]
          }
        },
        "analyzer" : {
          "lower_keyword" : {
            "type" : "custom",
            "tokenizer": "keyword",
            "filter" : ["lowercase"],
            "char_filter" : ["no_special"]
          }
        }
      }
    },
    "mapping" : {
      "_all" : {
        "enabled" : false
      },
      "properties" : {
        "name" : {
          "type" : "string",
          "analyzer" : "lower_keyword"
        },
        "simpleName" : {
          "type" : "string",
          "analyzer" : "lower_keyword"
        },
        "enclosingModule" : {
          "type" : "string",
          "analyzer" : "lower_keyword"
        },
        "enclosingClass" : {
          "type" : "string",
          "analyzer" : "lower_keyword"
        },
        "kind" : {
          "type" : "string",
          "index" : "no"
        },
        "params" : {
          "type" : "string",
          "index" : "no"
        },
        "path" : {
          "type" : "string",
          "index" : "no"
        },
        "summaryHtml" : {
          "type" : "string",
          "index" : "no"
        },
        "sourceUrl" : {
          "type" : "string",
          "index" : "no"
        },
        "functions" : {
          "type" : "object",
          "enabled" : false
        },
        "classes" : {
          "type" : "object",
          "enabled" : false
        },
        "constants" : {
          "type" : "object",
          "enabled" : false
        },
        "methods" : {
          "type" : "object",
          "enabled" : false
        },
        "classMethods" : {
          "type" : "object",
          "enabled" : false
        },
        "suggest" : {
          "type" : "completion",
          "analyzer" : "lower_keyword"
        }
      }
    }
  },
  "updates" : [
      eos

      Dir["#{@dir_path}/library/*.html"].each do |file_path|
      #Dir["#{@dir_path}/library/mmap.html"].each do |file_path|

        simple_filename = File.basename(file_path)

        #unless simple_filename.end_with?('stdtypes.html')
        #  next
        #end

        puts "Opening file '#{file_path}' ..."

        File.open(file_path) do |f|
          doc = Nokogiri::HTML(f)
          process_file(doc, simple_filename, out)
        end
      end

      out.write("\n  ]\n}")

      puts "Found #{@num_names_found} names."
    end
  end

  def summarize_members(members)
    members.map do |member|
      summarized = member.dup
      [:name, :enclosingModule, :enclosingClass, :kind, :sourceCodeUrl, :methods, :classMethods, :attributes].each do |key|
        summarized.delete(key)
      end
      summarized
    end
  end

  def process_file(doc, simple_filename, out)
    module_name = nil
    module_summary = nil
    module_name_holder = doc.css('h1 a.reference .py-mod .pre').first

    if module_name_holder
      module_name = module_name_holder.text()
      module_summary = doc.css('h1 a.reference').first.attr('title').strip
    else
      puts "No module name found for file '#{simple_filename}'"

      simple_filebase = simple_filename.gsub(/\.html$/, '')

      module_name = simple_filebase.split('/').last
      module_summary = doc.css('h1').text().gsub(/^\s*\d*\.\s*/, '').gsub('¶', '').strip
    end


    source_code_label = doc.css('strong').find do |node|
      node.text().strip == 'Source code:'
    end

    source_code_url = nil
    if source_code_label
      source_code_url = source_code_label.next_element().attr('href')
    end


    module_functions = []
    module_classes = []
    module_constants = []

    doc.css('dl.function, dl.data, dl.exception').each do |dl|
      begin
        output_doc = process_member(simple_filename, source_code_url, module_name, nil, dl)

        write_doc(out, output_doc)

        kind = output_doc[:kind]
        if kind == 'function'
          module_functions << output_doc
        elsif  kind == 'class'
          module_classes << output_doc
        elsif  kind == 'constant'
          module_constants << output_doc
        end

        @num_names_found += 1
      rescue => e
        puts "Exception: '#{e.message}'"
        puts e.backtrace
        puts "Ignoring function element #{dl.to_s}"
      end
    end

    doc.css('dl.class').each do |dl|
      class_doc = process_member(simple_filename, source_code_url, module_name, nil, dl)

      debug("prelim class doc = #{class_doc.to_json}")

      class_name = class_doc[:name]

      debug("prelim class name = #{class_name}")

      methods = []
      class_methods = []

      dl.css('dl.attribute, dl.method, dl.classmethod').each do |inner_dl|
        begin
          output_doc = process_member(simple_filename, source_code_url, module_name, class_name, inner_dl)

          if @first_document
            @first_document = false
          else
            out.write(",\n")
          end

          out.write(output_doc.to_json)

          kind = output_doc[:kind]
          if kind == 'method'
            methods << output_doc
          elsif kind == 'class'
            class_methods << output_doc
          end

          @num_names_found += 1
        rescue => e
          puts "Exception: '#{e.message}'"
          puts e.backtrace
          puts "Ignoring function element #{inner_dl.to_s}"
        end
      end

      class_doc[:methods] = summarize_members(methods)
      class_doc[:classMethods] = summarize_members(class_methods)
      write_doc(out, class_doc)

      module_classes << class_doc
    end


    module_doc = {
      name: module_name,
      simpleName: module_name,
      summaryHtml: module_summary,
      kind: 'module',
      path: simple_filename,
      sourceCodeUrl: source_code_url,
      functions: summarize_members(module_functions),
      classes: summarize_members(module_classes),
      constants: summarize_members(module_constants),
      suggest: {
        input: module_name,
        output: module_name
      }
    }

    write_doc(out, module_doc)
  end

  def process_member(simple_filename, source_code_url, module_name, class_name, dl)
    kind = dl.attr('class')

    if kind == 'data'
      kind = 'constant'
    end

    dt = dl.css('dt')[0]

    begin
      simple_name = dt.css('.descname')[0].text()
    rescue => e
      puts "Can't read simple_name for filename #{simple_filename}, module = #{module_name}, class = #{class_name}, dl = #{dl.text}"
      return
    end

    #debug "Found element #{dt.to_s}"

    full_name = nil

    if kind == 'class'
      full_name = (dt.css('.descclassname')[0].text() rescue '') + simple_name
    else
      full_name = dt.attr('id')
    end

    summary_html = dl.css('dd').inner_html().strip
    relative_path = simple_filename + (dl.css('a.headerlink')[0].attr('href') rescue '')

    debug "Full name = '#{full_name}'"
    debug "Class name = '#{class_name}'"
    debug "Simple name = '#{simple_name}'"
    debug "Summary HTML = '#{summary_html}'"
    debug "Path = '#{relative_path}'"

    output_doc = {
      name: full_name,
      simpleName: simple_name,
      enclosingClass: class_name,
      enclosingModule: module_name,
      kind: kind,
      path: relative_path,
      summaryHtml: summary_html,
      sourceCodeUrl: source_code_url,
      suggest: {
        input: [full_name, simple_name].uniq.compact,
        output: full_name
      }
    }

    if (kind != 'attribute') && (kind != 'constant')
      params = dt.css('em').collect do |em|
        em.text().strip()
      end

      debug "Parameters = (#{params.join(',')})"

      output_doc[:params] = params
    end

    output_doc
  end

  def write_doc(out, doc)
    if @first_document
      @first_document = false
    else
      out.write(",\n")
    end

    out.write(doc.to_json)
  end
end

output_filename = 'python-doc.json'

if ARGV.length > 1
  output_filename = ARGV[1]
end

PythonLibraryPopulator.new(ARGV[0], output_filename).populate

system("bzip2 -kf #{output_filename}")
