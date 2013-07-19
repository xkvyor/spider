module HTMLParser
    DEBUG = false

    def log(str)
        puts str
    end

    class HTMLNode
        def initialize(param = {})
            @p = nil
            @p = param['parent'] if param.include?'parent'
            @c = []
            @c = param['children'] if param.include?'children'
            @tag = ''
            @tag = param['tag'] if param.include?'tag'
            @attr = {}
            @attr = param['attr'] if param.include?'attr'
        end

        def each(&block)
            block.call(self)
            @c.each do |node|
                node.each(&block)
            end
        end

        def display_html_tree(pre)
            if @c.length == 0
                if self.instance_of?HTMLStringNode
                    puts "--"*pre + "node:#{@tag} [#{@cont}] close"
                else
                    puts "--"*pre + "node:#{@tag} close"
                end
                return
            end
            puts "--"*pre + "node:#{@tag}" if @c.length > 0
            @c.each do |n|
                n.display_html_tree(pre+1)
            end
            puts "--"*pre + "close:#{@tag}" if @c.length > 0
        end

        def rebuild_html(pre = 0)
            if (@tag =~ /^DOCTYPE$/i)
                return "<!DOCTYPE #{@attr['attr']}>\n"
            end
            if (self.instance_of?HTMLStringNode)
                return "#{'  '*pre}#{@cont}\n" if @cont =~ /\S/um
                return ''
            end
            if ['hr', 'br', 'meta', 'link', 'input', 'img'].include?@tag
                str = "  "*pre + "<#{@tag}"
                @attr.each do |k, v|
                    str += " #{k}=\"#{v}\""
                end
                str += " />\n"
                return str
            end
            str = ''
            if pre >= 0
                str = "  "*pre + "<#{@tag}"
                @attr.each do |k, v|
                    str += " #{k}=\"#{v}\""
                end
                str += ">\n"
            end
            @c.each do |kid|
                str += kid.rebuild_html(pre+1)
            end
            if pre >= 0
                str += "  "*pre + "</#{@tag}>\n"
            end
            return str
        end

        attr_accessor :p, :c, :tag, :attr
    end

    class HTMLDocument < HTMLNode
        def get_elements_by_tag(tag)
            result = []
            self.each do |node|
                result << node if node.tag == tag
            end
            return result
        end

        def get_elements_by_class(class_name)
            result = []
            self.each do |node|
                result << node if node.attr['class'] != nil and node.attr['class'].split(/\s+/).include?class_name
            end
            return result
        end

        def get_elements_by_id(id)
            result = []
            self.each do |node|
                result << node if node.attr['id'] == id
            end
            return result
        end

        def display_html_tree(pre = -1)
            @c.each do |n|
                n.display_html_tree(0)
            end
        end

        def rebuild_html(pre = -1)
            str = ''
            @c.each do |node|
                str += node.rebuild_html(pre+1)
            end
            return str
        end
    end

    class HTMLStringNode < HTMLNode
        def initialize(parent, str)
            @cont = str
            super({
                'parent' => parent,
                'tag' => '#STRING#'
            })
        end

        attr_accessor :cont
    end

    class HTMLParser
        def initialize(target_page = '')
            @page = target_page
            @len = @page.length
            @p = 0
        end

        def blank?
            return true if ["\t", "\r", " ", "\n", "\f"].include?@page[@p]
            return false
        end

        def valid_tag_name?
            return true if @page[@p] =~ /[\w-]/u
            return false
        end

        def valid_attr_name?
            return true if @page[@p] =~ /[\w-]/u
            return false
        end

        def valid_attr_value?
            return false if @page[@p] =~ /[>\s]/u
            return true
        end

        def consume()
            beg = @p
            while @p < @len and blank?
                @p += 1
            end
            return @p - beg
        end

        def match(expect)
            if expect == @page[@p]
                @p += 1
            else
                raise "[syntax error] expect '#{expect}' but '#{@page[@p]}' at #{@p}/#{@len}"
            end
        end

        def match_word(word)
            idx = @page.index(word, @p)
            raise "[syntax error] '#{word}' not found since #{@p}/#{@len}" if idx == nil
            @p = idx + word.length
        end

        def get_tag_name
            beg = @p
            while @p < @len and valid_tag_name?
                @p += 1
            end
            return @page[beg..@p-1]
        end

        def get_attr_name
            beg = @p
            while @p < @len and valid_attr_name?
                @p += 1
            end
            return @page[beg..@p-1]
        end

        def get_attr_value(terminator = nil)
            beg = @p
            if terminator != nil
                pos = @page.index(terminator, @p)
                pos = @len if pos == nil
                @p = pos
                return @page[beg..@p-1]
            end
            while @p < @len and valid_attr_value?
                @p += 1
            end
            return @page[beg..@p-1]
        end

        def get_content
            return '' if @page[@p] == '<'
            ter = @page.index('<', @p)
            ter = @len if ter == nil
            beg = @p
            @p = ter
            content = @page[beg..ter-1]
            content.sub!(/^\s*/, '')
            content.sub!(/\s*$/, '')
            # raise "error: #{beg}:#{@page[beg]}..#{@p}:#{@page[@p]}" if content == '>'
            return content
        end

        def get_script
            beg = @p
            match_word('</script>')
            return @page[beg..@p-10]
        end

        def get_style
            beg = @p
            match_word('</style>')
            return @page[beg..@p-9]
        end

        def match_doctype(parent)
            tmp = HTMLNode.new({
                'parent' => parent
            })

            tmp.tag = get_tag_name
            consume
            beg = @p
            match_word('>')
            tmp.attr['attr'] = @page[beg..@p-2]
            consume

            parent.c << tmp
        end

        def node(parent, unclosed = [])
            match '<'
            if @page[@p] == '!'
                @p += 1
                if @page[@p] == '-' and @page[@p+1] == '-'
                    match('-')
                    match('-')
                    beg = @p
                    match_word('-->')
                    log "comment #{@page[beg..@p-4]}" if DEBUG
                else
                    match_doctype(parent)
                end
                return
            end

            tmp = HTMLNode.new({
                'parent' => parent
            })

            tmp.tag = get_tag_name

            log "new node #{tmp.tag}" if DEBUG

            consume

            if (@page[@p] == '/' or @page[@p] == "\\")
                parent.c << tmp
                pos = @page.index('>', @p)
                if pos == nil
                    @p = @len
                    log "[warning] could not found a '>'" if DEBUG
                else
                    @p = pos
                    match('>')
                end
                log "#{tmp.tag} close" if DEBUG
                return
            end

            while @p < @len and @page[@p] != '>'
                key = get_attr_name
                if key == ''
                    log "[warning] invalid character at #{@p}/#{@len}" if DEBUG
                    @p += 1
                    consume
                    next
                end
                val = ''
                if @page[@p] == '='
                    match '='
                    if @page[@p] == "'" or @page[@p] == '"'
                        ter = @page[@p]
                        @p += 1
                        val = get_attr_value(ter)
                        match(ter)
                    else
                        val = get_attr_value
                    end
                end

                tmp.attr[key] = val

                log "#{key} = #{val}" if DEBUG

                consume

                if @page[@p] == '/' and @page[@p+1] == '>'
                    parent.c << tmp
                    @p += 2
                    log "#{tmp.tag} close" if DEBUG
                    return
                end
            end

            match '>'

            if tmp.tag == 'script'
                script = get_script
                tmp.c << HTMLStringNode.new(tmp, script) if script =~ /\S/um
                log "#{tmp.tag} close" if DEBUG
                parent.c << tmp
                return
            end

            if tmp.tag == 'style'
                style = get_style
                tmp.c << HTMLStringNode.new(tmp, style) if style =~ /\S/um
                log "#{tmp.tag} close" if DEBUG
                parent.c << tmp
                return
            end

            if ['hr', 'br', 'meta', 'link', 'input', 'img'].include?tmp.tag
                parent.c << tmp
                log "#{tmp.tag} close" if DEBUG
                return
            end

            while @p < @len
                content = get_content
                tmp.c << HTMLStringNode.new(tmp, content) if content.length > 0
                break unless @p < @len
                if @page[@p] == '<' and @page[@p+1] != '/'
                    chain = unclosed.clone
                    chain << tmp
                    node(tmp, chain)
                else
                    match '<'
                    match '/'
                    close_tag_name = get_tag_name
                    blkcnt = consume
                    match '>'
                    if tmp.tag == close_tag_name
                        parent.c << tmp
                        log "#{tmp.tag} complete" if DEBUG
                        return
                    else
                        unclosed.each do |pp|
                            if pp.tag == close_tag_name
                                log "[warning] <#{tmp.tag}> is not close correctly at #{@p}/#{@len}" if DEBUG
                                @p -= (close_tag_name.length + blkcnt + 3)
                                parent.c << tmp
                                return
                            end
                        end
                        log "[warning] ignore close tag </#{close_tag_name}> at #{@p}/#{@len}" if DEBUG
                        next
                    end
                end
            end

            log "[warning] <#{tmp.tag}> close incorrectly at #{@p}/#{@len}" if DEBUG
            parent.c << tmp
        end

        def parse
            @p = 0

            root = HTMLDocument.new({
                'parent' => nil,
                'tag' => '#HTMLDOCUMENT#',
            })

            while @p < @len
                node root if @page[@p] == '<'
                content = get_content
                root.c << HTMLStringNode.new(root, content) if content =~ /\S/um
            end

            return root
        end

        def set_page(page)
            @page = page
            @p = 0
            @len = @page.length
        end
    end  
end
