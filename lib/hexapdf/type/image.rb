# -*- encoding: utf-8 -*-
#
#--
# This file is part of HexaPDF.
#
# HexaPDF - A Versatile PDF Creation and Manipulation Library For Ruby
# Copyright (C) 2014-2017 Thomas Leitner
#
# HexaPDF is free software: you can redistribute it and/or modify it
# under the terms of the GNU Affero General Public License version 3 as
# published by the Free Software Foundation with the addition of the
# following permission added to Section 15 as permitted in Section 7(a):
# FOR ANY PART OF THE COVERED WORK IN WHICH THE COPYRIGHT IS OWNED BY
# THOMAS LEITNER, THOMAS LEITNER DISCLAIMS THE WARRANTY OF NON
# INFRINGEMENT OF THIRD PARTY RIGHTS.
#
# HexaPDF is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public
# License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with HexaPDF. If not, see <http://www.gnu.org/licenses/>.
#
# The interactive user interfaces in modified source and object code
# versions of HexaPDF must display Appropriate Legal Notices, as required
# under Section 5 of the GNU Affero General Public License version 3.
#
# In accordance with Section 7(b) of the GNU Affero General Public
# License, a covered work must retain the producer line in every PDF that
# is created or manipulated using HexaPDF.
#++

require 'zlib'
require 'hexapdf/error'
require 'hexapdf/stream'
require 'hexapdf/image_loader'

module HexaPDF
  module Type

    # Represents an image XObject of a PDF document.
    #
    # See: PDF1.7 s8.8
    class Image < Stream

      # The structure that is returned by the Image#info method.
      Info = Struct.new(:type, :width, :height, :color_space, :indexed, :components,
                        :bits_per_component, :writable, :extension)

      define_field :Type,             type: Symbol,          default: :XObject
      define_field :Subtype,          type: Symbol,          required: true, default: :Image
      define_field :Width,            type: Integer,         required: true
      define_field :Height,           type: Integer,         required: true
      define_field :ColorSpace,       type: [Symbol, Array]
      define_field :BitsPerComponent, type: Integer
      define_field :Intent,           type: Symbol,          version: '1.1'
      define_field :ImageMask,        type: Boolean,         default: false
      define_field :Mask,             type: [Stream, Array], version: '1.3'
      define_field :Decode,           type: Array
      define_field :Interpolate,      type: Boolean,         default: false
      define_field :Alternates,       type: Array,           version: '1.3'
      define_field :SMask,            type: Stream,          version: '1.4'
      define_field :SMaskInData,      type: Integer,         version: '1.5'
      define_field :StructParent,     type: Integer,         version: '1.3'
      define_field :ID,               type: PDFByteString,   version: '1.3'
      define_field :OPI,              type: Dictionary,      version: '1.2'
      define_field :Metadata,         type: Stream,          version: '1.4'
      define_field :OC,               type: Dictionary,      version: '1.5'

      # Returns the source path that was used when creating the image object.
      #
      # This value is only set when the image object was created by using the image loading
      # facility and not when the image is part of a loaded PDF file.
      attr_accessor :source_path

      # Returns an Info structure with information about the image.
      #
      # Available accessors:
      #
      # type::
      #    The type of the image. Either :jpeg, :jp2, :jbig2, :ccitt or :png.
      # width::
      #    The width of the image.
      # height::
      #    The height of the image.
      # color_space::
      #    The color space the image uses. Either :rgb, :cmyk, :gray or :other.
      # indexed::
      #    Whether the image uses an indexed color space or not.
      # components::
      #    The number of color components of the color space, or -1 if the number couldn't be
      #    determined.
      # bits_per_component::
      #    The number of bits per color component.
      # writable::
      #    Whether the image can be written by HexaPDF.
      # extension::
      #    The file extension that would be used when writing the file. Either jpg, jpx or png. Only
      #    meaningful when writable is true.
      def info
        result = Info.new
        result.width = self[:Width]
        result.height = self[:Height]
        result.bits_per_component = self[:BitsPerComponent]
        result.indexed = false
        result.writable = true

        filter, rest = *self[:Filter]
        case filter
        when :DCTDecode
          result.type = :jpeg
          result.extension = 'jpg'.freeze
        when :JPXDecode
          result.type = :jp2
          result.extension = 'jpx'.freeze
        when :JBIG2Decode
          result.type = :jbig2
        when :CCITTFaxDecode
          result.type = :ccitt
        else
          result.type = :png
          result.extension = 'png'.freeze
        end

        if rest || ![:FlateDecode, :DCTDecode, :JPXDecode, nil].include?(filter)
          result.writable = false
        end

        color_space, = *self[:ColorSpace]
        if color_space == :Indexed
          result.indexed = true
          color_space, = *document.deref(self[:ColorSpace][1])
        end
        case color_space
        when :DeviceRGB, :CalRGB
          result.color_space = :rgb
          result.components = 3
        when :DeviceGray, :CalGray
          result.color_space = :gray
          result.components = 1
        when :DeviceCMYK
          result.color_space = :cmyk
          result.components = 4
          result.writable = false if result.type == :png
        else
          result.color_space = :other
          result.components = -1
          result.writable = false if result.type == :png
        end

        result
      end

      # :call-seq:
      #   image.write(basename)
      #   image.write(io)
      #
      # Saves this image XObject to the file with the given name and appends the correct extension
      # (if the name already contains this extension, the name is used as is), or the given IO
      # object.
      #
      # Raises an error if the image format is not supported.
      #
      # The output format and extension depends on the image type as returned by the #info method:
      #
      # :jpeg:: Saved as a JPEG file with the extension '.jpg'
      # :jp2:: Saved as a JPEG2000 file with the extension '.jpx'
      # :png:: Saved as a PNG file with the extension '.png'
      def write(name_or_io)
        info = self.info

        unless info.writable
          raise HexaPDF::Error, "PDF image format not supported for writing"
        end

        io = if name_or_io.kind_of?(String)
               File.open(name_or_io.sub(/\.#{info.extension}\z/, '') + "." + info.extension, "wb")
             else
               name_or_io
             end

        if info.type == :jpeg || info.type == :jp2
          source = stream_source
          while source.alive? && (chunk = source.resume)
            io << chunk
          end
        else
          write_png(io, info)
        end
      ensure
        io.close if io && name_or_io.kind_of?(String)
      end

      private

      # Writes the image as PNG to the given IO stream.
      def write_png(io, info)
        io << ImageLoader::PNG::MAGIC_FILE_MARKER

        color_type = if info.indexed
                       ImageLoader::PNG::INDEXED
                     elsif info.color_space == :rgb
                       ImageLoader::PNG::TRUECOLOR
                     else
                       ImageLoader::PNG::GREYSCALE
                     end

        io << png_chunk('IHDR', [info.width, info.height, info.bits_per_component,
                                 color_type, 0, 0, 0].pack('N2C5'))

        if key?(:Intent)
          # PNG s11.3.3.5
          intent = ImageLoader::PNG::RENDERING_INTENT_MAP.rassoc(self[:Intent]).first
          io << png_chunk('sRGB', intent.chr) <<
            png_chunk('gAMA', [45455].pack('N')) <<
            png_chunk('cHRM', [31270, 32900, 64000, 33000, 30000, 60000, 15000, 6000].pack('N8'))
        end

        if color_type == ImageLoader::PNG::INDEXED
          palette_data = document.deref(self[:ColorSpace][3])
          palette_data = palette_data.stream unless palette_data.kind_of?(String)
          palette = ''.b
          if info.color_space == :rgb
            palette = palette_data[0, palette_data.length - palette_data.length % 3]
          else
            palette_data.each_byte {|byte| palette << byte << byte << byte}
          end
          io << png_chunk('PLTE', palette)
        end

        if self[:Mask].kind_of?(Array) && self[:Mask].each_slice(2).all? {|a, b| a == b} &&
            (color_type == ImageLoader::PNG::TRUECOLOR || color_type == ImageLoader::PNG::GREYSCALE)
          io << png_chunk('tRNS', self[:Mask].each_slice(2).map {|a, _| a}.pack('n*'))
        end

        filter, = *self[:Filter]
        if filter == :FlateDecode && self[:DecodeParms] && self[:DecodeParms][:Predictor].to_i >= 10
          data = stream_source
        else
          flate_decode = GlobalConfiguration.constantize('filter.map', :FlateDecode)
          data = flate_decode.encoder(stream_decoder, Predictor: 15, Colors: 1, Columns: info.width,
                                      BitsPerComponent: info.bits_per_component)
        end
        io << png_chunk('IDAT', Filter.string_from_source(data))

        io << png_chunk('IEND', '')
      end

      # Returns the binary representation of the PNG chunk for the given chunk type and data.
      def png_chunk(type, data = nil)
        [data.to_s.length].pack("N") << type << data.to_s <<
          [Zlib.crc32(data, Zlib.crc32(type))].pack("N")
      end

    end

  end
end
