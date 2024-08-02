# spec/resourcer_spec.rb
require "spec_helper"

RSpec.describe Resourcer do
  it "has a version number" do
    expect(Resourcer::VERSION).not_to be nil
  end

  it "does something useful" do
    expect(false).to eq(true)
  end
end