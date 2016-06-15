package Mojo::Webqq::Plugin::KnowledgeBase2;
our $PRIORITY = 3;
use List::Util qw(first);
sub retrieve_db {
    my ($file) = @_;
    my $db = {};
    open my $fd,"<",$file or die $!;
    while(<$fd>){
        chomp;
        my($space,$key,$content) = split;
        push @{ $db->{$space}{$key} }, $content;
    }
    close $fd;
    return $db;
}
sub store_db {
    my($db,$file) = @_;
    open my $fd,">",$file or die $!;
    for my $space (keys %$db){
        for my $key (keys %{$db->{$space}}){
            #print $key,$space,join("|",@{$hash->{$space}{$key}});
            for $answer (@{$db->{$space}{$key}}){
                print $fd $space,"\t",$key,"\t",$answer,"\n";
            }
        }
    }
    close $fd;
}
sub call{
    my $client = shift;
    my $data = shift;
    my ($file_size, $file_mtime);
    $data->{mode} = 'fuzzy' if not defined $data->{mode};
    my $file = $data->{file} || './KnowledgeBase.txt';
    my $learn_command = defined $data->{learn_command}?quotemeta($data->{learn_command}):'learn|学习';
    my $delete_command = defined $data->{delete_command}?quotemeta($data->{delete_command}):'delete|del|删除';
    my $base = {};
    if(-e $file){
        ($file_size, $file_mtime) = (stat $file)[7, 9];
        $base = retrieve_db($file);
    }
    $client->interval($data->{check_time} || 10,sub{
        return if not -e $file;
        return if not defined $file_size; 
        return if not defined $file_mtime; 
        my ($size, $mtime) = (stat $file)[7, 9]; 
        if($size != $file_size or $mtime != $file_mtime){
            $file_size = $size;
            $file_mtime = $mtime;
            $base = retrieve_db($file);        
        }
    });
    #$client->timer(120,sub{nstore $base,$file});
    my $callback = sub{
        my($client,$msg) = @_;
        return if $msg->type !~ /^message|group_message|dicsuss_message|sess_message$/;
        if($msg->type eq 'group_message'){
            return if $data->{is_need_at} and $msg->type eq "group_message" and !$msg->is_at;
            return if ref $data->{ban_group}  eq "ARRAY" and first {$_=~/^\d+$/?$msg->group->gnumber eq $_:$msg->group->gname eq $_} @{$data->{ban_group}};
            return if ref $data->{allow_group}  eq "ARRAY" and !first {$_=~/^\d+$/?$msg->group->gnumber eq $_:$msg->group->gname eq $_} @{$data->{allow_group}}
        }
        if($msg->content =~ /^(?:$learn_command)(\*?)
                            \s+
                            (?|"([^"]+)"|'([^']+)'|([^\s"']+))
                            \s+
                            (?|"([^"]+)"|'([^']+)'|([^\s"']+))
                            /xs){
            $msg->allow_plugin(0);
            return if ref $data->{learn_operator} eq "ARRAY" and ! first {$_ eq $msg->sender->qq} @{$data->{learn_operator}};
            my($c,$q,$a) = ($1,$2,$3);
            return unless defined $q;
            return unless defined $a;
            my $space = '';
            if(defined $c and $c eq "*"){
                $space = '__全局__';
            }
            else{
                $space = $msg->type eq "message"?"__我的好友__":$msg->group->displayname;
            }
            $q=~s/^\s+|\s+$//g;
            $a=~s/^\s+|\s+$//g;
            $a=~s/\\n/\n/g;
            push @{ $base->{$space}{$q} }, $a;
            store_db($base,$file);
            ($file_size, $file_mtime)= (stat $file)[7, 9];
            $client->reply_message($msg,"知识库[ $q →  $a ]" . ($space eq '__全局__'?"*":"") . "添加成功",sub{$_[1]->msg_from("bot")}); 

        }   
        elsif($msg->content =~ /^(?:$delete_command)(\*?)
                            \s+
                            (?|"([^"]+)"|'([^']+)'|([^\s"']+))
                            /xs){
            $msg->allow_plugin(0);
            return if ref $data->{delete_operator} eq "ARRAY" and ! first {$_ eq $msg->sender->qq} @{$data->{delete_operator}};
            #return if $msg->sender->id ne $client->user->id;
            my($c,$q) = ($1,$2);
            $q=~s/^\s+|\s+$//g;
            return unless defined $q;
            my $space = '';
            if(defined $c and $c eq "*"){
                $space = '__全局__';
            }
            else{
                $space = $msg->type eq "message"?"__我的好友__":$msg->group->displayname;
            }
            delete $base->{$space}{$q}; 
            store_db($base,$file);
            ($file_size, $file_mtime)= (stat $file)[7, 9];
            $client->reply_message($msg,"知识库[ $q ]". ($space eq '__全局__'?"*":"") . "删除成功"),sub{$_[1]->msg_from("bot")};
        }
        else{
            return if $msg->msg_class eq "send" and $msg->msg_from ne "api" and $msg->msg_from ne "irc";
            my $content = $msg->content;
            $content =~s/^[a-zA-Z0-9_]+: ?// if $msg->msg_from eq "irc";
            my $space = $msg->type eq "message"?"__我的好友__":$msg->group->displayname;
            #return unless exists $base->{$space}{$content};
            if($data->{mode} eq 'regex'){
                my @match_keyword;
                for my $keyword (keys %{$base->{$space}}){
                    next if not $content=~/$keyword/;
                    push @match_keyword,$keyword;
                }
                if(@match_keyword == 0){
                    $space = '__全局__';
                    for my $keyword (keys %{$base->{$space}}){
                        next if not $content=~/$keyword/;
                        push @match_keyword,$keyword;
                    }
                }
                return if @match_keyword == 0;
                $msg->allow_plugin(0);
                my $keyword = $match_keyword[int rand @match_keyword];
                my $len = @{$base->{$space}{$keyword}};
                my $reply = $base->{$space}{$keyword}->[int rand $len];
                $reply .= "\n--匹配模式『$keyword』" . ($space eq '__全局__'?"*":"");
                $client->reply_message($msg,$reply,sub{$_[1]->msg_from("bot")});
            }
            elsif($data->{mode} eq 'fuzzy'){
                my @match_keyword;
                for my $keyword (keys %{$base->{$space}}){
                    next if not $content=~/\Q$keyword\E/;
                    push @match_keyword,$keyword;
                }
                if(@match_keyword == 0){
                    $space = '__全局__';
                    for my $keyword (keys %{$base->{$space}}){
                        next if not $content=~/$keyword/;
                        push @match_keyword,$keyword;
                    }
                }
                return if @match_keyword == 0;
                $msg->allow_plugin(0);
                my $keyword = $match_keyword[int rand @match_keyword];
                my $len = @{$base->{$space}{$keyword}};
                my $reply = $base->{$space}{$keyword}->[int rand $len];
                $reply .= "\n--匹配关键字『$keyword』" . ($space eq '__全局__'?"*":"");
                $client->reply_message($msg,$reply,sub{$_[1]->msg_from("bot")});
            }
            else{
                $space = '__全局__' if not exists $base->{$space}{$content};
                return if not exists $base->{$space}{$content};
                $msg->allow_plugin(0);
                my $len = @{$base->{$space}{$content}};
                return if $len ==0;
                $client->reply_message($msg,$base->{$space}{$content}->[int rand $len] . ($space eq '__全局__'?"*":""),sub{$_[1]->msg_from("bot")}); 
            }
        }
    };
    $client->on(receive_message=>$callback);
    $client->on(send_message=>$callback);
}
1;
