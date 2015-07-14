# -*- encoding: utf-8 -*-

require 'test_helper'
require 'hexapdf/pdf/document'
require 'hexapdf/pdf/type/catalog'

describe HexaPDF::PDF::Type::Catalog do
  before do
    @doc = HexaPDF::PDF::Document.new
    @catalog = @doc.add(Type: :Catalog)
  end

  it "creates the page tree on access" do
    assert_nil(@catalog[:Pages])
    pages = @catalog.pages
    assert_equal(:Pages, pages.type)
  end

  describe "validation" do
    it "creates the page tree if necessary" do
      refute(@catalog.validate(auto_correct: false))
      assert(@catalog.validate)
    end
  end
end