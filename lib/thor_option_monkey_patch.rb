# thor_option_monkey_patch.rb
module ThorOptionMonkeyPatch

  def usage(padding = 0)
    sample = if banner && !banner.to_s.empty?
               "#{switch_name}=#{banner}".dup
             else
               switch_name
             end

    sample = "[#{sample}]".dup unless required?

    # Thor would add `--no-*` aliases here. We don't like those. Sorry, Thor.

    if aliases.empty?
      (" " * padding) << sample
    else
      "#{aliases.join(', ')}, #{sample}"
    end
  end

  # We also don't like defaults that show up on a new line. Keep it clean, Thor!
  def show_default?
    return false
  end

end

Thor::Option.prepend(ThorOptionMonkeyPatch)