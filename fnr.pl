#---------------------------------------------------------------------------
#  gui
#---------------------------------------------------------------------------

package MyFrame;
use Wx qw(:everything);
use Wx::Event qw(:everything);
use base 'Wx::Frame';

use Mouse;
use IO::All;
use Config::General;
use threads;
use Encode qw(encode decode from_to);
use WWW::Mechanize;
use HTML::TableExtract;
use Data::TreeDumper;
use Smart::Comments;
use List::MoreUtils qw(any);

use version; our $VERSION = qv('0.0.5');

our %text;
my $os = $ENV{OS};
$os eq 'Windows_NT' ? require 'lang/cht_big5.pm' : require 'lang/cht_utf8.pm';
my $encoding = $text{encoding};

has 'input'   => ( is => 'rw', isa => 'ArrayRef' );
has 'output'  => ( is => 'rw', isa => 'Str' );
has 'config'  => ( is => 'rw', isa => 'Str' );
has 'previous_file'      => ( is => 'rw', isa => 'Str' );
has 'previous_directory' => ( is => 'rw', isa => 'Str' );
has 'id_list' => ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );

sub new {
    my ($class, %args) = @_;
    my $title = sprintf "%s%s", $text{name}, $VERSION->normal;

    my $self = $class->SUPER::new(
        undef, -1, $title,
        [200,200], [700,350],
        wxDEFAULT_FRAME_STYLE|wxNO_FULL_REPAINT_ON_RESIZE|wxCLIP_CHILDREN,
    );

    Wx::InitAllImageHandlers();

    # menu
    my $menubar  = Wx::MenuBar->new;

    my $file = Wx::Menu->new;
    $file->Append( wxID_EXIT, "$text{exit}(&E)" );

	my $wxID_SETUP_INPUT  = 100;
	my $wxID_SETUP_OUTPUT = 101;
    my $setup = Wx::Menu->new;
    $setup->Append( $wxID_SETUP_INPUT,  "$text{input}(&I)" );
    $setup->Append( $wxID_SETUP_OUTPUT, "$text{output}(&O)" );

    my $help = Wx::Menu->new;
    $help->Append( wxID_ABOUT, "$text{about}(&A)" );

    $menubar->Append( $file,   "$text{file}(&F)" );
    $menubar->Append( $setup,  "$text{setup}(&S)" );
    $menubar->Append( $help,   "$text{help}(&H)" );

    $self->SetMenuBar( $menubar );

    EVT_MENU( $self, wxID_ABOUT, \&on_about );
    EVT_MENU( $self, $wxID_SETUP_INPUT,  \&on_setup_input  );
    EVT_MENU( $self, $wxID_SETUP_OUTPUT, \&on_setup_output );
    EVT_MENU( $self, wxID_EXIT, sub { $self->Close } );

    # split window
    my $split = Wx::SplitterWindow->new(
        $self, -1, wxDefaultPosition, wxDefaultSize,
        wxNO_FULL_REPAINT_ON_RESIZE|wxCLIP_CHILDREN,
    );

    my $text = Wx::TextCtrl->new(
        $split, -1, q{},
        wxDefaultPosition, wxDefaultSize,
        wxTE_READONLY|wxTE_MULTILINE|wxNO_FULL_REPAINT_ON_RESIZE,
    );

    my $log = Wx::LogTextCtrl->new($text);
    Wx::Log::SetActiveTarget($log);

    my $panel = Wx::Panel->new($split, -1);

    # buttons
    my $run_btn  = Wx::Button->new( $panel, -1, $text{exec}, [490,5] );
    my $exit_btn = Wx::Button->new( $panel, -1, $text{exit}, [590,5] );

    EVT_BUTTON( $self, $run_btn,  \&on_run);
    EVT_BUTTON( $self, $exit_btn, sub { $self->Close() } );

    $split->SplitHorizontally( $text, $panel, 255 );

    # misc
    $self->SetIcon( Wx::GetWxPerlIcon() );
    Wx::LogMessage(sprintf "%s%s%s!", $text{greeting}, $text{name}, $VERSION->normal);

	$self->config('fnr.cfg');

	if (! -e $self->config) {
		q{} > io($self->config); # create a empty file
		$self->on_setup_input;
		$self->on_setup_output;
	}
	else {
		# read config
		my $config = Config::General->new($self->config);
		my %config = $config->getall;
		$self->input(ref $config{input} ? $config{input} : [$config{input}]);
		$self->output($config{output});
	}

    return $self;
}

#---------------------------------------------------------------------------
#  setup
#---------------------------------------------------------------------------

sub on_setup_input {
	my $self = shift;

	my $url = 'http://www.funddj.com/y/yb/YP303000.djhtm';
	#my $url = 'http://www.funddj.com/y/yb/YP303001.djhtm';

	my $mech = WWW::Mechanize->new;
	$mech->get($url);
	my @company_links = grep { $_->url_abs =~ /yp020000/ } $mech->links;
	my @company_names = map { decode('big5', $_->text) } @company_links;

	my $dialog = Wx::MultiChoiceDialog->new( $self, "$text{fund}$text{company}$text{select}", "$text{select}$text{company}", [@company_names] );
	my @selected = $self->input ? @{ $self->input } : ();

	if (@selected) {
		$dialog->SetSelections(@selected);
		Wx::LogMessage( "$text{previous}$text{select}: " );
		Wx::LogMessage( join ", ", (map { $company_names[$_] } @selected) );
	}

	if( $dialog->ShowModal == wxID_CANCEL ) {
		Wx::LogMessage( "$text{user}$text{cancel}$text{select}" );
	} else {
		my @selections = $dialog->GetSelections;
		Wx::LogMessage( "$text{user}$text{select}: " );
		Wx::LogMessage( join ", ", (map { $company_names[$_] } @selections) );
		$self->input(\@selections);

		my $config = Config::General->new($self->config);
		my %config = $config->getall;
		$config{input} = $self->input;
		$config->save_file($self->config, \%config);
	}

	$dialog->Destroy;
}

sub on_setup_output {
	my $self = shift;

    my $dialog = Wx::FileDialog->new(
		$self, "$text{output}$text{setup}", $self->previous_directory || q{},
        $self->previous_file || q{},
        'Plain text files (*.txt)|*.txt|All files (*.*)|*.*',
        wxFD_OPEN );

    if( $dialog->ShowModal != wxID_CANCEL ) {
        my $path = $dialog->GetPath;

        if( $path ) {
			Wx::LogMessage("$text{output}$text{setup}");
			Wx::LogMessage("$path");
			$self->output($path);

			my $config = Config::General->new($self->config);
			my %config = $config->getall;
			$config{output} = $self->output;
			$config->save_file($self->config, \%config);
        }

        $self->previous_directory( $dialog->GetDirectory );
    }

    $dialog->Destroy;
}

#---------------------------------------------------------------------------
#  exec
#---------------------------------------------------------------------------

sub on_run {
    my $self = shift;

    Wx::LogMessage("$text{exec}$text{ing}...");

	my $thr = threads->create( sub { 
		$self->retrieve_nav;
	} );

	if ( $ENV{OS} ne 'Windows_NT' ) {
		$thr->join;
	}

	# <Problem>
	# ubuntu:
	# 1. without use threads, it will get stuck until parse and retrieve finished
	# 2. use threads and join will get the same result
	# 3. use threads but not join sometimes can't show full message on log window

	# windows:
	# 1. looks fine even without threads, but can't move window when exec
	# 2. use threads and join will hang up

    return;
}

sub retrieve_nav {
    my $self = shift;
    my $output = $self->output;
    unlink $output if -e $output;
    "$text{label}\n" >> io($output);
    Wx::LogMessage($text{label});

	my $url = 'http://www.funddj.com/y/yb/YP303000.djhtm';
	#my $url = 'http://www.funddj.com/y/yb/YP303001.djhtm';

	my $mech = WWW::Mechanize->new;
	$mech->get($url);
	my @company_links = grep { $_->url_abs =~ /yp020000/ } $mech->links;

	my $index = -1;
	my @company_selections = @{$self->input};
	foreach my $company_link (@company_links) {
		$index++;
		next unless any { $_ == $index } @company_selections;
		my $company_name = $company_link->text;
		my $company_url  = $company_link->url_abs;
		$mech->get($company_url);
		
		my @fund_links = grep { $_->url_abs =~ /yp010000/ } $mech->links;

		foreach my $fund_link (@fund_links) {
			my $fund_name = $fund_link->text;
			my $log_fund_name = decode('big5', $fund_name);
			my $fund_url  = $fund_link->url_abs;
			$mech->get($fund_url);
			my $content = $mech->content;

			my $te = HTML::TableExtract->new;
			$te->parse($content);
			my @tables = $te->tables;
			my $table= $tables[3];
			my @values = @{ $tables[3]->rows->[1] }[0..2];
			my $result = sprintf "%-50s %-15s %-10s %-10s", 
				$fund_name, 
				$values[0], 
				$values[1], 
				$values[2];
			"$result\n" >> io($output);

			my $log_result = sprintf "%-50s %-15s %-10s %-10s", 
				$log_fund_name, 
				$values[0], 
				$values[1], 
				$values[2];
			Wx::LogMessage($log_result);
		}
		"\n" >> io($output);
	}

    Wx::LogMessage($text{output});
    Wx::LogMessage($self->output);
    Wx::LogMessage("$text{retrieve}$text{done}!");
}

#---------------------------------------------------------------------------
#  misc
#---------------------------------------------------------------------------

sub on_about {   
    my $self = shift;
    my $info = Wx::AboutDialogInfo->new;
    $info->SetName($text{name});
    $info->SetVersion($VERSION->normal);
    $info->SetDescription($text{desc});
    $info->SetCopyright('Copyright (c) 2008 Alec Chen');
    $info->AddDeveloper('Alec Chen <alec@cpan.org>');
    $info->AddArtist('Alec Chen <alec@cpan.org>');
    Wx::AboutBox($info);
    return;
}

#---------------------------------------------------------------------------
#  main
#---------------------------------------------------------------------------

package main;

my $app = Wx::SimpleApp->new;
my $frame = MyFrame->new;
$frame->Show;
$app->MainLoop;
