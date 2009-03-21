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

use version; our $VERSION = qv('0.0.1');

our %text;
my $os = $ENV{OS};
$os eq 'Windows_NT' ? require 'lang/cht_big5.pm' : require 'lang/cht_utf8.pm';
my $encoding = $text{encoding};

has 'input'   => ( is => 'rw', isa => 'Str' );
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
    my $run_btn  = Wx::Button->new( $panel, -1, $text{exec}, [500,5] );
    my $exit_btn = Wx::Button->new( $panel, -1, $text{exit}, [590,5] );

    EVT_BUTTON( $self, $run_btn,  \&on_run);
    EVT_BUTTON( $self, $exit_btn, sub { $self->Close() } );

    $split->SplitHorizontally( $text, $panel, 255 );

    # misc
    $self->SetIcon( Wx::GetWxPerlIcon() );
    Wx::LogMessage(sprintf "%s%s%s!", $text{greeting}, $text{name}, $VERSION->normal);

	$self->config('sqr.cfg');

	if (! -e $self->config) {
		q{} > io($self->config); # create a empty file
		$self->on_setup_input;
		$self->on_setup_output;
	}
	else {
		# read config
		my $config = Config::General->new($self->config);
		my %config = $config->getall;
		$self->input($config{input});
		$self->output($config{output});
	}

    return $self;
}

#---------------------------------------------------------------------------
#  setup
#---------------------------------------------------------------------------

sub on_setup_input {
	my $self = shift;

    my $dialog = Wx::FileDialog->new(
		$self, "$text{input}$text{setup}", $self->previous_directory || q{},
        $self->previous_file || q{},
        'Microsoft Excel files (*.xls)|*.xls|All files (*.*)|*.*',
        wxFD_OPEN|wxFD_FILE_MUST_EXIST );

    if( $dialog->ShowModal != wxID_CANCEL ) {
        my $path = $dialog->GetPath;

        if( $path ) {
			Wx::LogMessage("$text{input}$text{setup}");
			Wx::LogMessage("$path");
			$self->input($path);

			my $config = Config::General->new($self->config);
			my %config = $config->getall;
			$config{input} = $self->input;
			$config->save_file($self->config, \%config);
        }

        $self->previous_directory( $dialog->GetDirectory );
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
    Wx::LogMessage($text{input});
    Wx::LogMessage($self->input);
    Wx::LogMessage("$text{analyze}Excel...");

	my $thr = threads->create( sub { 
		$self->parse_excel;
		$self->retrieve_quote;
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

sub retrieve_quote {
    my $self = shift;
    my $output = $self->output;
    unlink $output if -e $output;
    "$text{label}\n" >> io($output);
    Wx::LogMessage($text{label});

    my $agent = Yahoo::TW::Stock->new( encoding => $encoding );
    my @id_list = @{$self->id_list};
	### @id_list

    foreach my $id (@id_list) {
        my @data = $agent->fetch($id);
		# use sprintf for format command instead
		my $data = join q{ }, @data;
		### $data
        "$data\n" >> io($output);
        Wx::LogMessage($data);
    }

    Wx::LogMessage($text{output});
    Wx::LogMessage($self->output);
    Wx::LogMessage("$text{retrieve}$text{done}!");
}

sub parse_excel {
    my $self = shift;

    my @id_list;
    my $input = $self->input;

    my $excel = Spreadsheet::ParseExcel::Workbook->Parse($input);
    my $sheet = $excel->{Worksheet}->[0];

    my $row = 1;
    while (1) {
        my $cell = $sheet->{Cells}[$row][0];
        last unless $cell;
        last if $row > 1000; # need better fool proof
        my $id = $cell->{Val};
        push @id_list, $id;
        $row++;
    }

    $self->id_list(\@id_list);
    Wx::LogMessage("$text{analyze}$text{done}!");
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
