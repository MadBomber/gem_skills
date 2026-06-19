# frozen_string_literal: true

require "test_helper"

class FrontmatterTest < Minitest::Test
  FM = Gem::Skill::Frontmatter

  BODY = <<~MD.chomp
    # tty-spinner v0.9.3

    ## Overview
    `tty-spinner` renders animated terminal spinners for CLI tasks; reach for it
    when building interactive terminal commands, not for logs.

    ## Installation
    gem "tty-spinner"
  MD

  # --- slug ---

  def test_slug_passes_through_valid_hyphen_case
    assert_equal "tty-spinner", FM.slug("tty-spinner")
  end

  def test_slug_hyphenates_underscores
    assert_equal "ruby-llm", FM.slug("ruby_llm")
  end

  def test_slug_downcases_and_collapses_invalid_runs
    assert_equal "rails-html-sanitizer", FM.slug("Rails__HTML--Sanitizer")
  end

  def test_slug_trims_leading_and_trailing_hyphens
    assert_equal "gem", FM.slug("__gem__")
  end

  def test_slug_falls_back_when_empty
    assert_equal "skill", FM.slug("___")
  end

  def test_slug_caps_length_without_trailing_hyphen
    slug = FM.slug("a" * 50 + "_tail")
    assert_operator slug.length, :<=, 40
    refute slug.end_with?("-")
  end

  # --- description_for ---

  def test_description_uses_overview_and_appends_version
    desc = FM.description_for("tty-spinner", "0.9.3", BODY)
    assert_includes desc, "renders animated terminal spinners"
    assert_includes desc, "(tty-spinner v0.9.3)"
    refute_includes desc, "\n", "description must be a single line"
  end

  def test_description_strips_angle_brackets
    body = "## Overview\nUse <Foo> with bar.\n"
    desc = FM.description_for("g", "1.0.0", body)
    refute_includes desc, "<"
    refute_includes desc, ">"
  end

  def test_description_falls_back_without_overview
    desc = FM.description_for("mygem", "2.0.0", "# mygem\n\nNo overview here.")
    assert_includes desc, "mygem"
  end

  # --- build ---

  def test_build_prepends_valid_frontmatter
    out = FM.build("tty-spinner", "0.9.3", BODY)
    assert out.start_with?("---\n")
    fm = out[/\A---\n(.*?)\n---/m, 1]
    assert_match(/^name: tty-spinner$/, fm)
    assert_match(/^description: ".+"$/, fm)
    assert_includes out, "# tty-spinner v0.9.3"
  end

  def test_build_is_idempotent
    once  = FM.build("tty-spinner", "0.9.3", BODY)
    twice = FM.build("tty-spinner", "0.9.3", once)
    assert_equal once, twice
  end

  def test_build_replaces_existing_frontmatter
    seeded = "---\nname: wrong\ndescription: \"old\"\n---\n\n#{BODY}"
    out    = FM.build("tty-spinner", "0.9.3", seeded)
    assert_match(/^name: tty-spinner$/, out[/\A---\n(.*?)\n---/m, 1])
    refute_includes out, "name: wrong"
    assert_equal 2, out.scan(/^---\s*$/).count, "exactly one frontmatter block (two --- delimiters)"
  end

  def test_yaml_quote_escapes_quotes_and_backslashes
    assert_equal %("a \\"b\\" c"), FM.yaml_quote('a "b" c')
    assert_equal %("a\\\\b"), FM.yaml_quote('a\\b')
  end
end
