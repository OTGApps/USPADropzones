require 'json'
require 'open-uri'
require 'bundler'
Bundler.require

class String
  def string_between_markers marker1, marker2
    self[/#{Regexp.escape(marker1)}(.*?)#{Regexp.escape(marker2)}/m, 1]
  end
end

class DZScraper
  def urls
    page = Nokogiri::HTML(open(local_files.first))
    page.css('div#NavTabs li.Level2 a').map{ |e| URI.parse(e[:href]) }
  end

  def local_files
    %w(california Colorado alabama florida arizona).map{|s| "local_files/#{s}.html"}
  end

  def scrape_local
    scrape(local_files)
  end

  def scrape_online
    scrape(urls)
  end

  def scrape(urls)
    dzs = {
      type: 'FeatureCollection',
      features: []
    }
    urls.map do |lf|
      puts "Scraping #{lf}"
      page = Nokogiri::HTML(open(lf))
      dzs[:features] += parse(page).compact
    end
    dzs
  end

  def parse(page)
    page.css('table').last.css('td').map do |td|
      next if td.text.strip == '' || !td.text.include?("LAT:")

      dz_data = {
        type: 'Feature',
        properties: {},
        geometry: {
          type: 'Point',
          coordinates: []
        }
      }

      dz_data[:properties][:anchor] = td.css('a').first['name']
      dz_data[:properties][:name] = td.css('span.subhead').first.text

      url = td.css('a[target="_blank"]')
      dz_data[:properties][:url] = url.first['href'] if url.is_a?(Array)

      dz_data[:properties].merge!(attributes(td))

      # Grab the lat and lng
      dz_data[:geometry][:coordinates] = [dz_data[:properties][:lng].to_f, dz_data[:properties][:lat].to_f]

      # Fix Skydive Taft
      if dz_data[:properties][:lng].start_with?("-199")
        dz_data[:geometry][:coordinates][0] = dz_data[:properties][:lng].gsub('199', '119').to_f
      end

      # Fix Oklahoma Skydiving Center && Skydive Chelan
      if dz_data[:properties][:name] == 'Oklahoma Skydiving Center' || dz_data[:properties][:name] == 'Skydive Chelan'
        dz_data[:geometry][:coordinates][0] = ("-" + dz_data[:properties][:lng]).to_f
      end

      # Remove lat and lng from the properties array
      dz_data[:properties].reject!{ |k| k == :lat || k == :lng }

      dz_data
    end
  end

  def attributes(xml)
    atts = {}
    xml.css('span').select{|s| s.to_s.strip != ''}.each do |s|
      text = s.text.strip.delete('-')
      text = text.split(' ').last if text.start_with?('USPA') || text.strip.end_with?('Services:')
      text = text.split(' ').first if text.start_with?('Distance')
      text = text[0...-1] if text[-1] == ':'
      ts = text.downcase.to_sym

      atts[:email] = js_to_string(s.next_element) if ts == :email

      next if text.start_with?("*") || s.next_sibling.text.strip == ""
      atts[ts] = s.next_sibling.text.strip
    end

    atts[:location] = get_location(xml)
    atts[:description] = get_description(xml)
    [:services, :training, :aircraft].each do |s|
      atts[s] = atts[s].split(',').map(&:strip) if atts[s]
    end
    atts
  end

  # This translates the obfuscated email address from javascript
  def js_to_string(js)
    xml = js.text.string_between_markers('String.fromCharCode(', '))').split(',').map{|i| i.to_i.chr(Encoding::UTF_8)}.join
    Nokogiri::HTML(xml).css('a').text
  end

  # Finds the location array in the HTML
  def get_location(xml)
    xml.to_s.string_between_markers('Location:</span>', '<br><br>')
      .split("\r\n")
      .select{ |s| s.strip != ''}
      .map{ |s| s.strip.gsub('<br>', '').squeeze(' ').gsub(' ,', ',') }
  end

  # Gets the description of the dropzone
  def get_description(xml)
    xml.to_s.gsub("\r\n", '').string_between_markers('<br><br>','<br><br><span class="title">LAT').split('<br><br>').last.strip.squeeze('  ')
  end

end

dzs = DZScraper.new

File.open("../dropzones-new.geojson","w") do |f|
  f.write(dzs.scrape_local.to_json)
  # f.write(dzs.scrape_online.to_json)
end
