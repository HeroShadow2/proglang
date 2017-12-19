-module(bmp_image).
-export([main/1]).
-define(BPP, 3).
-include("image_rec.hrl").
-compile(export_all).

% { {width,0}, {height,0}, {contents,<<>>}, {headers, <<>>} }
load(jpeg, _FileName) -> {error, not_implemented};
load(bmp, FileName) ->
    case file:read_file(FileName) of
        {ok, Contents} -> parse_contents(Contents);
        SomethingElse  -> SomethingElse
    end.

parse_contents(Contents) ->
    case Contents of
        <<"BM",_:64,Off:32/little,_:32,
            Width:32/signed-little,
            Height:32/signed-little,
            _Rest/binary>>
                        ->
                        Headers = binary_part(Contents,0,Off),
                        PixelDataSize = size(Contents)-Off,
                        % io:fwrite("Head size: ~p, cont.size: ~p~n", [size(Headers), PixelDataSize]),
                        PixelData = binary_part(Contents,Off,PixelDataSize),
                        Image = #image{
                            width = Width,
                            height = Height,
                            headers = Headers,
                            contents = PixelData
                        },
                        {ok, Image}
                        ;
                        
        _               -> {error, wrong_format}
    end.

save(Image, OutputFileName) -> 
    file:write_file(OutputFileName, Image#image.headers, [write]),
    file:write_file(OutputFileName, Image#image.width, [append]),
    file:write_file(OutputFileName, Image#image.height, [append]),
    file:write_file(OutputFileName, Image#image.contents, [append]).

get_size(Image) ->
    W = Image#image.width,
    H = Image#image.height,
    {W, H}.
    
hide_data(Pixel, Data) ->
    <<B:5, _:3, G:5, _:3, R:5, _:3>> = Pixel,
    <<B_:3, G_:3, R_:3>> = <<Data:9>>,
    NewPixel = <<B:5, B_:3, G:5, G_:3, R:5, R_:3>>,
    % io:write([Pixel, NewPixel]),
    % io:fwrite(" ~p   ~p ~p ~p~n",[Data, B_, G_, R_]),
    NewPixel.

get_symbol(Pixel) ->
    <<_:5, B:3, _:5, G:3, _:5, R:3>> = Pixel,
    Bin = <<B:3, G:3, R:3>>,
    <<Symbol:9>> = Bin,
    % io:write(Symbol),
    % io:fwrite(" ~p   ~p ~p ~p~n",[Bin, B, G, R]),
    Symbol.

hide_string(Contents, [], _) -> Contents;
hide_string(Contents, StringToHide, Position) ->
    [DataToHide | Rest] = StringToHide,
    BeginContests = binary_part(Contents, 0, Position),
    % io:write(BeginContests),
    HideHere = binary_part(Contents, Position, ?BPP),
    EndContests = binary_part(Contents, Position + ?BPP, byte_size(Contents) - Position - ?BPP),
    NewPixel = hide_data(HideHere, DataToHide),
    FixedContents =  <<BeginContests/binary, NewPixel/binary, EndContests/binary>>,
    hide_string(FixedContents, Rest, Position + ?BPP).


hide_string_size(Contents, Data) ->
    Bin = <<Data:24>>,
    EndContests = binary_part(Contents, ?BPP, byte_size(Contents) - ?BPP),
    <<Bin/binary, EndContests/binary>>.

get_secret_size(Contents) ->
    <<Data:24>> = binary_part(Contents, 0, ?BPP),
    Data.


get_data(_, SecretString, _, 0) -> SecretString;
get_data(Contents, SecretString, Position, RestSize) ->
    HideHere = binary_part(Contents, Position, ?BPP),
    Secret = get_symbol(HideHere),
    get_data(Contents, SecretString ++ [Secret], Position + ?BPP, RestSize - 1).

cut_string(String, [], _) -> String;
cut_string(String, _, 0) -> String;
cut_string(String, Rest, Size) ->
    [ToAdd | NewRest] = Rest,
    cut_string(String ++ [ToAdd], NewRest, Size - 1).

main([InputFileName, OutputFileName, StringToHide | _ ]) ->
    {ok, Image} = load(bmp, InputFileName),
    {W, H} = get_size(Image),
    % io:fwrite("Read bitmap of size ~p x ~p~n", [W, H]),
    CuttedString = cut_string([], StringToHide, W * H - 1),
    Size = erlang:length(CuttedString),
    io:write(Size),
    io:fwrite("~n"),
    io:fwrite(CuttedString),
    io:fwrite("~n"),
    NewContents_ = hide_string(Image#image.contents, CuttedString, ?BPP),
    NewContents = hide_string_size(NewContents_, Size),
    NewImage = #image{
                            width = Image#image.width,
                            height = Image#image.height,
                            headers = Image#image.headers,
                            contents = NewContents
                        },
    save(NewImage, OutputFileName),
    {ok, SecretImage} = load(bmp, OutputFileName),

    SecretSize = get_secret_size(SecretImage#image.contents),
    io:write(SecretSize),
    io:fwrite("~n"),
    SecretString = get_data(SecretImage#image.contents, [], ?BPP, SecretSize),
    io:fwrite(SecretString),
    io:fwrite("~n").
