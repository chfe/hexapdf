# -*- encoding: utf-8 -*-

require 'hexapdf/configuration'

module HexaPDF

  # This class provides utility functions for PDF documents. It is available through the
  # Document#utils method.
  #
  # Some functions can't be attributed to a single "manager" object. For example, while embedding
  # a file can be done within a Filespec object, loading an image from a file as a PDF object
  # doesn't have such a place. Such functions are available via this class.
  class DocumentUtils

    # This module provides methods for managing the images embedded in a PDF file; images
    # themselves are represented by the Type::Image class.
    #
    # Since an image can be used as a mask for another image, not all image objects found in a PDF
    # are really used as images. Such cases are all handled by this class automatically.
    module Images

      # :call-seq:
      #   images.add_image(file)            -> image
      #   images.add_image(io)              -> image
      #
      # Adds the image from the given file or IO to the PDF and returns the image object.
      #
      # If the image has been added to the PDF before (i.e. if there is an image object with the
      # same path name), the already existing image object is returned.
      def add_image(file_or_io)
        name = if file_or_io.kind_of?(String)
                 file_or_io
               elsif file_or_io.respond_to?(:to_path)
                 file_or_io.to_path
               end
        if name
          name = File.absolute_path(name)
          image = each_image.find {|im| im.source_path == name}
        end
        unless image
          image = image_loader_for(file_or_io).load(@document, file_or_io)
          image.source_path = name
        end
        image
      end

      # :call-seq:
      #   images.each_image {|image| block }   -> images
      #   images.each_image                    -> Enumerator
      #
      # Iterates over all images in the PDF.
      #
      # Note that only real images are yielded which means, for example, that images used as soft
      # mask are not.
      def each_image(&block)
        images = @document.each(current: false).select do |obj|
          obj[:Subtype] == :Image && !obj[:ImageMask]
        end
        masks = images.each_with_object([]) do |image, temp|
          temp << image[:Mask] if image[:Mask].kind_of?(Stream)
          temp << image[:SMask] if image[:SMask].kind_of?(Stream)
        end
        (images - masks).each(&block)
      end

      private

      # Returns the image loader (see ImageLoader) for the given file or IO stream or raises an
      # error if no suitable image loader is found.
      def image_loader_for(file_or_io)
        GlobalConfiguration['image_loader'].each_index do |index|
          loader = GlobalConfiguration.constantize('image_loader', index) do
            raise HexaPDF::Error, "Couldn't retrieve image loader from configuration"
          end
          return loader if loader.handles?(file_or_io)
        end

        raise HexaPDF::Error, "Couldn't find suitable image loader"
      end

    end


    # This module provides methods for managing file specification of a PDF file.
    #
    # Note that for a given PDF file not all file specifications may be found, e.g. when a file
    # specification is only a string. Therefore this module can only handle those file
    # specifications that are indirect file specification dictionaries with the /Type key set.
    module Files

      # :call-seq:
      #   files.add_file(filename, name: File.basename(filename), description: nil, embed: true) -> file_spec
      #   files.add_file(io, name:, description: nil)                      -> file_spec
      #
      # Adds the file or IO to the PDF and returns the corresponding file specification object.
      #
      # Options:
      #
      # name::
      #     The name that should be used for the file path. This name is also for registering the
      #     file in the EmbeddedFiles name tree.
      #
      # description::
      #     A description of the file.
      #
      # embed::
      #     When an IO object is given, it is always embedded and this option is ignored.
      #
      #     When a filename is given and this option is +true+, then the file is embedded. Otherwise
      #     only a reference to it is stored.
      #
      # See: HexaPDF::Type::FileSpecification
      def add_file(file_or_io, name: nil, description: nil, embed: true)
        name ||= File.basename(file_or_io) if file_or_io.kind_of?(String)
        if name.nil?
          raise ArgumentError, "The name argument is mandatory when given an IO object"
        end

        spec = @document.add(Type: :Filespec)
        spec.path = name
        spec[:Desc] = description if description
        spec.embed(file_or_io, name: name, register: true) if embed || !file_or_io.kind_of?(String)
        spec
      end

      # :call-seq:
      #   files.each_file(search: false) {|file_spec| block }   -> files
      #   files.each_file(search: false)                        -> Enumerator
      #
      # Iterates over indirect file specification dictionaries of the PDF.
      #
      # By default, only the file specifications in their standard locations, namely in the
      # EmbeddedFiles name tree and in the page annotations, are returned. If the +search+ option is
      # +true+, then all indirect objects are searched for file specification dictionaries which is
      # much slower.
      def each_file(search: false)
        return to_enum(__method__, search: search) unless block_given?

        if search
          @document.each(current: false) do |obj|
            yield(obj) if obj.type == :Filespec
          end
        else
          seen = {}
          tree = @document.catalog[:Names] && @document.catalog[:Names][:EmbeddedFiles]
          tree.each_entry do |_, spec|
            seen[spec] = true
            yield(spec)
          end if tree

          @document.pages.each_page do |page|
            next unless page[:Annots]
            page[:Annots].each do |annot|
              annot = @document.deref(annot)
              next unless annot[:Subtype] == :FileAttachment
              spec = @document.deref(annot[:FS])
              yield(spec) unless seen.key?(spec)
              seen[spec] = true
            end
          end
        end

        self
      end

    end

    include Images
    include Files

    # Creates a new DocumentUtils object for the given PDF document.
    def initialize(document)
      @document = document
    end

  end

end