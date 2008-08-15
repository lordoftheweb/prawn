# encoding: utf-8

# text.rb : Implements PDF text primitives
#
# Copyright May 2008, Gregory Brown. All Rights Reserved.
#
# This is free software. Please see the LICENSE and COPYING files for details.
require "zlib"

module Prawn
  class Document
    module Text
      # Draws text on the page. If a point is specified via the <tt>:at</tt>
      # option the text will begin exactly at that point, and the string is
      # assumed to be pre-formatted to properly fit the page.
      #
      # When <tt>:at</tt> is not specified, Prawn attempts to wrap the text to
      # fit within your current bounding box (or margin box if no bounding box
      # is being used ). Text will flow onto the next page when it reaches
      # the bottom of the margin_box. Text wrap in Prawn does not re-flow
      # linebreaks, so if you want fully automated text wrapping, be sure to
      # remove newlines before attempting to draw your string.  
      #
      #   pdf.text "Hello World", :at => [100,100]
      #   pdf.text "Goodbye World", :at => [50,50], :size => 16
      #   pdf.text "Will be wrapped when it hits the edge of your bounding box"
      #
      # If your font contains kerning pairs data that Prawn can parse, the 
      # text will be kerned by default.  You can disable this feature by passing
      # <tt>:kerning => false</tt>.
      #
      # == Encoding
      #
      # Note that strings passed to this function should be encoded as UTF-8.
      # If you get unexpected characters appearing in your rendered document, 
      # check this.
      #
      # If the current font is a built-in one, although the string must be
      # encoded as UTF-8, only characters that are available in ISO-8859-1
      # are allowed.
      #
      # If an empty box is rendered to your PDF instead of the character you 
      # wanted it usually means the current font doesn't include that character.
      #
      def text(text,options={})
        # we'll be messing with the strings encoding, don't change the users
        # original string
        text = text.dup
          
        font.normalize_encoding(text)

        if options.key?(:kerning)
          options[:kerning] = false unless font.metrics.has_kerning_data?
        else
          options[:kerning] = true if font.metrics.has_kerning_data?
        end                     
        
        options[:size] ||= font.size

        return wrapped_text(text,options) unless options[:at]
                
        x,y = translate(options[:at]) 
               
        font.size(options[:size]) do                 
          add_text_content(text,x,y,options)
        end  
        
        if options[:hold_position]         
          # FIXME: Ugly hacka hacka
          self.y = y + font.height + font.metrics.descender / 1000.0 * font.size
          @text_x_pos = x + font.width_of(text) - bounds.absolute_left        
        end
      end   
                       
      private 

      def move_text_position(dy)
         (y - dy) < @margin_box.absolute_bottom ? start_new_page : self.y -= dy       
      end

      # TODO: Get kerning working with wrapped text
      def wrapped_text(text,options) 
        options[:align] ||= :left      
        @text_x_pos ||= 0 
        
        font.size(options[:size]) do
          text = font.metrics.naive_wrap(text, bounds.right, font.size, 
            :kerning => options[:kerning], :offset => @text_x_pos ) 

          lines = text.lines
          line_y = nil 
                                                                              
          lines.each do |e|                                                   
            line_y = self.y           
            
            move_text_position( font.height + 
                                font.metrics.descender / 1000.0 * font.size )                                 
                           
            line_width = font.width_of(e)
            case(options[:align]) 
            when :left
              x = @bounding_box.absolute_left + @text_x_pos
            when :center
              x = @bounding_box.absolute_left + @text_x_pos +
                (@bounding_box.width - line_width) / 2.0
            when :right
              x = @bounding_box.absolute_right - line_width - @text_x_pos
            end
                               
            add_text_content(e,x,y,options)
            ds = -font.metrics.descender / 1000.0 * font.size 
            move_text_position(options[:spacing] || ds )     
            @text_x_pos = 0
          end 
          
          if options[:hold_position]  
            self.y = line_y 
            @text_x_pos = font.width_of(lines.last)
          end
          
        end
      end  
      
      def add_text_content(text, x, y, options)
        text = font.metrics.convert_text(text,options)

        add_content %Q{
          BT
          /#{font.identifier} #{font.size} Tf
          #{x} #{y} Td
        }  

        add_content Prawn::PdfObject(text, true) <<
          " #{options[:kerning] ? 'TJ' : 'Tj'}\n"

        add_content %Q{
          ET
        }
      end       
      
      module StyleParser

        module_function

        TAG_PATTERN = %r{(</?[ib]>)}

        STATES = {
          "<b>" => { :normal => :bold,
                      :italic => :bold_italic },
          "</b>" => { :bold_italic => :italic,
                      :bold => :normal },
          "<i>" => { :normal => :italic,
                      :bold => :bold_italic },
          "</i>" => { :bold_italic => :bold,
                      :italic => :normal }
        }


        def process(text) #:nodoc:
          segments = text.split(TAG_PATTERN).delete_if{|x| x.empty? }
          state = :normal
          segments.map! do |s|
            if new_state = STATES.key?(s) && STATES[s][state]
              state = new_state
            else
              s
            end
          end
          segments
        end

        def style_tag?(text)
          !!(text =~ TAG_PATTERN)
        end

      end
      
    end
  end
end
