Spec::Matchers.define :have_apache_directive do |directive, value|
  match do |actual|
    if actual.respond_to?(:content)
      actual = actual.content
    end
    
    if actual =~ /^\s*#{directive}\s+(\w+)[^#\n]*/
      @found_value = $1
      value.to_s == @found_value
    else
      false
    end
  end

  failure_message_for_should do |actual|
    if @found_value
      "expected to <#{value}> for <#{directive}>, but got #{@found_value}"
    else
      "expected to find a value for <#{directive}>"
    end
  end
  
  failure_message_for_should_not do |actual|
    "expected that #{actual} would not be a precise multiple of #{expected}"
  end

  description do
    "be a precise multiple of #{expected}"
  end
  
end
