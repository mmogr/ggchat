# What is true today

Every claim here that can be tested names its test in a marker, and
`scripts/check_readme_claims.sh` fails CI when a marker names a test that
does not exist. This is the app's behaviour as a list of such claims; the
[README](../README.md) is the short version.

Each claim names the test that keeps it true.

- A stream captured from a running gglib parses to the same events whether
  it arrives whole or one byte at a time.
  <!-- test: SSEParserTests.testFeedingOneByteAtATimeGivesTheSameItems -->
- When the request asks for progress, gglib's first chunks carry it and no
  `choices` key; reasoning arrives as `reasoning_content`; the usage chunk
  has empty `choices`. All three decode.
  <!-- test: WireTests.testFirstChunkHasNoChoicesKeyAndStillDecodes -->
  <!-- test: WireTests.testReasoningArrivesAsReasoningContent -->
  <!-- test: WireTests.testUsageChunkHasEmptyChoicesAndCachedTokens -->
- A server's error sentence is shown verbatim, and every code the app knows
  from modelpipe and gglib says which machine to look at, that the request
  itself was refused, or that the answer is to wait. The side named is the
  side that wrote the refusal, which is not always the side you are sitting
  at. The codes are an enum, so the mapping is exhaustive by the compiler
  rather than by a list someone remembers to extend, and each half of it is
  checked against the list modelpipe or gglib publishes: a code gglib adds
  fails a test until it is given an answer or filed as one not shown. A key
  the serving machine no longer admits says so, and the line after it says
  where a new key comes from, which depends on the kind of provider: a pipe
  pairs again with `gglib remote invite`, and a server's key is checked in
  its settings.
  <!-- test: ErrorTests.testAKeyTheServingMachineNoLongerAdmitsSaysSo -->
  <!-- test: AppModelRefusalTests.testTheAdviceUnderARefusalFollowsTheKindOfProvider -->
  <!-- test: ErrorTests.testServerMessageIsRenderedVerbatim -->
  <!-- test: ErrorTests.testEveryDocumentedCodeNamesWhereToLook -->
  <!-- test: ErrorTests.testThePublishedHalfOfTheVocabularyIsModelpipesOwnList -->
  <!-- test: ErrorTests.testGglibsHalfOfTheVocabularyIsGglibsOwnList -->
  <!-- test: ErrorTests.testTheSideNamedIsTheSideThatWroteTheRefusal -->
  <!-- test: ErrorTests.testAMachineThatIsMerelyBusySaysToWaitRatherThanNamingASide -->
- A message carries its images by reference: the SHA-256 of the bytes,
  their type and size, which is how gglib names a stored image. A request
  reads the bytes from this device's store, once per image, in one place
  for a send, Retry and a run's `PUT` sent again, and an image that cannot
  be read sends nothing. On the wire a turn with images is its text, then
  one `image_url` part per image in order; a turn with none is the bare
  string it always was, byte for byte. gglib's model list says which model
  reads images with `vision`. A direct chat to a model that cannot is
  refused by name either way it goes: the chat route answers 400 at once,
  and a run takes the `PUT` and then fails with the code. Each of gglib's
  six image codes says what to change, and an image's cost is gglib's own
  estimate.
  <!-- test: ImageRefTests.testTheIdIsTheSHA256OfTheBytesInLowercaseHex -->
  <!-- test: ImageRefTests.testItReadsAndWritesGGLibsAttachmentInfo -->
  <!-- test: ImageRefTests.testTheTokenEstimateIsGGLibsRule -->
  <!-- test: ImageRefTests.testTheModelListSaysWhichModelReadsImages -->
  <!-- test: ImageContentWireTests.testARequestWithNoImagesIsTheSameBytesAsBefore -->
  <!-- test: ImageContentWireTests.testATurnWithImagesIsItsTextThenEachImageInOrder -->
  <!-- test: ImageContentWireTests.testATurnOfImagesAloneHasNoTextPart -->
  <!-- test: ImageContentWireTests.testATurnNamingAnImageWithNoBytesIsNotEncoded -->
  <!-- test: ImageRefusalTests.testEachImageCodeSaysWhatToChange -->
  <!-- test: ImageRefusalTests.testTheChatRouteRefusesAnImageAtOnceByName -->
  <!-- test: ImageRefusalTests.testABodyOverTheLimitIsRefusedAsTooLarge -->
  <!-- test: ImageRefusalTests.testARunIsTakenThenFailsWithTheCode -->
  <!-- test: AppModelImageRequestTests.testARequestHoldsEveryImageItsTurnsNameReadOncePerImage -->
  <!-- test: AppModelImageRequestTests.testATurnsImageIsSentAndOneThatCannotBeReadSendsNothing -->
  <!-- test: AppModelImageRequestTests.testARunPutAgainCarriesItsImageOrIsGivenUpWithoutIt -->
  <!-- test: AppModelImageRequestTests.testARunToAModelThatCannotSeeEndsWithTheCodeAndWhatToDo -->
- In both composers the field has a row of its own, the local one's across
  the glass, with the add-image control and Draw in a toolbar under it and
  Send at the toolbar's trailing end, so the field is as wide as the
  composer however many controls the toolbar holds.
  <!-- test: ContextRingUITests.testAReplyRaisesTheRingAndItsSheetSaysTheCounts -->
- A transcript scrolled more than half a screen up offers a round button
  above the composer that takes it back to the latest message, and the
  next reply is followed from there; at its latest, and in a chat shorter
  than its screen, there is none. A chat at its latest stays there when the
  keyboard comes back up as a reply ends, and one scrolled up stays put.
  While a reply is coming, a chat at its latest follows it as it grows,
  even a few points short of its very bottom; one scrolled more than half
  a screen up, or with nothing coming, is left where it is.
  <!-- test: JumpToLatestTests.testAtTheBottomThereIsNoButton -->
  <!-- test: JumpToLatestTests.testTheComposersInsetIsNotCountedAsDistance -->
  <!-- test: JumpToLatestTests.testScrolledUpLessThanHalfAScreenThereIsNoButton -->
  <!-- test: JumpToLatestTests.testScrolledUpMoreThanHalfAScreenThereIsOne -->
  <!-- test: JumpToLatestTests.testAChatShorterThanItsScreenNeverHasOne -->
  <!-- test: JumpToLatestTests.testAChatAtItsLatestIsKeptThereWhenTheKeyboardComesUp -->
  <!-- test: JumpToLatestTests.testAChatScrolledUpStaysWhereItIsWhenTheKeyboardComesUpOrGoes -->
  <!-- test: JumpToLatestTests.testAChatAFewPointsShortOfItsLatestIsStillTakenThere -->
  <!-- test: JumpToLatestTests.testAChatAFewPointsShortOfItsLatestFollowsAReplyAsItGrows -->
  <!-- test: JumpToLatestTests.testAChatScrolledUpOrWithNothingComingIsNotFollowed -->
  <!-- test: JumpToLatestUITests.testAChatScrolledUpOffersAWayBackToItsLatestReply -->
- The composer stays open while a reply runs, so the next message is
  written as this one comes; Send waits for the reply to end, and the
  message is sent with it then. A Mac's chat open here does the same while
  the Mac writes.
  <!-- test: TypingDuringAReplyUITests.testTheNextMessageIsWrittenWhileAReplyRuns -->
- An image joins a draft through the photo picker, a paste or a drop, on
  iOS the paste as a row of the add-image menu, and every one goes through
  one downscale: turned upright by its orientation,
  2560 pixels on its long edge at most and never made larger, none of the
  original's metadata (its location included), a PNG while one fits in
  8 MiB and a JPEG otherwise, refused with a sentence when even that does not
  fit, and named by the SHA-256 of the bytes sent. The draft shows each with
  gglib's token estimate, and a turn of images alone is sent and drawn. A
  model gglib lists without `vision` cannot see: an image added for it, or a
  draft with images to it, is refused here with gglib's own sentence, the
  draft kept with its text and images, and a draft of text alone still goes
  to it; any other server is sent them. A turn the server refuses keeps its
  images for Retry. The bytes are kept once each beside the store, opened
  across the change both ways, deleted with the last turn that names them or
  taken back when a draft is refused partway, and gone after a reset.
  <!-- test: ImageDownscaleTests.testAnImageIsTurnedUprightByItsOrientation -->
  <!-- test: ImageDownscaleTests.testTheLongEdgeIsAtMost2560AndASmallImageIsNotMadeLarger -->
  <!-- test: ImageDownscaleTests.testAPNGStaysAPNGWhileItFitsAndOtherwiseIsAJPEG -->
  <!-- test: ImageDownscaleTests.testNothingOfTheOriginalsMetadataIsSent -->
  <!-- test: ImageDownscaleTests.testTheIdIsTheSHA256OfTheBytesSent -->
  <!-- test: AppModelImageSendTests.testOnlyAModelGGLibListsWithoutVisionCannotSee -->
  <!-- test: AppModelImageSendTests.testADraftWithAnImageToAModelThatCannotSeeIsRefusedHere -->
  <!-- test: AppModelImageSendTests.testATurnOfImagesAloneIsSentAndItsBytesAreKept -->
  <!-- test: AppModelImageSendTests.testADraftWhoseImageCannotBeKeptIsRefused -->
  <!-- test: AppModelImageSendTests.testATurnTheServerRefusesKeepsItsImagesForRetry -->
  <!-- test: AppModelImageSendTests.testEachImageInTheStripSaysWhatGGLibEstimatesItCosts -->
  <!-- test: AppModelImageSendTests.testAnImageAddedForAModelThatCannotSeeIsRefusedAtOnce -->
  <!-- test: AppModelImageSendTests.testARefusedDraftLeavesNoImageBehindThatNoTurnNames -->
  <!-- test: DraftTests.testARefusedDraftKeepsItsTextAndImagesAndATakenOneIsEmpty -->
  <!-- test: DraftTests.testTheSameImageAddedTwiceIsOne -->
  <!-- test: ConversationTests.testAFirstTurnOfImagesAloneIsCalledWhatItHolds -->
  <!-- test: ImageStoreTests.testATurnsImagesAndTheirBytesOutliveAReopening -->
  <!-- test: ImageStoreTests.testAnImageGoesWithTheLastTurnThatNamesIt -->
  <!-- test: ImageStoreTests.testAStoreOpensAcrossTheImagesChangeInBothDirections -->
  <!-- test: ImageStoreTests.testTheResetLeavesNoImageFileBehind -->
  <!-- test: FirstRunUITests.testAPastedImageIsSentAloneAndDrawnInTheTranscript -->
- A new conversation, from the list or the app's icon, is with the
  provider of the one open, a Mac's chat included, and with the first
  provider when none is open or the open one's provider was removed.
  Choosing a model changes that conversation alone, never a provider's
  default. The model pill opens one list of every provider's models, a
  section for each in the order the providers are listed, headed by its name
  and how its engine or pipe is ("not loaded", "connected", "last heard
  08:12"), the conversation's model ticked. Under each model is one line,
  "27B · Q8_0" read out of gglib's description and any other server's
  description as it came, and on This iPhone the model's size until its
  engine has described it. With two providers or more, chips filter the list
  to one, a choice this device keeps; past eight models a search finds one
  by its name or its line, and says when nothing matches. Opening the list
  lists each provider again, quietly, where its session is up: no pipe is
  dialled and no engine served for it. This iPhone's models are the ones
  installed on it, read from its library; a pipe that is down keeps the
  models it listed last, dimmed, and one that has listed none offers
  Connect, which dials it as the status pill's Reconnect does, its models
  arriving as it comes up; a server or This iPhone with none says "Not
  listed yet". The list is sized from the chat's height free of its top bar
  and the keyboard, so its search stays on screen with the keyboard up; at
  an accessibility text size it leaves more room for the stacked pills,
  keeps no chips, and its search scrolls with the rows.
  Picking a model on another provider moves the conversation there with that
  model, as a conversation whose provider was removed gets one, and drops
  the Thinking choice, the image model and the servers picked for the one
  left. A conversation whose reply is still being written stays where it was
  asked, its other providers' models dimmed and the list saying why.
  <!-- test: ModelDetailTests.testGGLibsDescriptionReadsAsItsSizeAndQuantization -->
  <!-- test: ModelDetailTests.testAPartGGLibCallsUnknownIsLeftOut -->
  <!-- test: ModelDetailTests.testAnotherDescriptionIsShownOnOneLine -->
  <!-- test: ModelListTests.testEveryProviderIsASectionInTheirOrderFilledWithoutDiallingOrServing -->
  <!-- test: ModelListTests.testAPipeThatIsDownShowsWhatItListedLastDimmed -->
  <!-- test: ModelListTests.testAPickOnAnotherProviderMovesTheConversationWithThatModel -->
  <!-- test: ModelListTests.testNothingMovesWhileAReplyIsWritten -->
  <!-- test: ModelListTests.testAConversationWithNoProviderGetsOneByAPick -->
  <!-- test: ModelListTests.testConnectDialsAPipeWithNothingListedAndItsModelsArrive -->
  <!-- test: ModelListTests.testOpeningTheListRelistsAPipeThatIsUp -->
  <!-- test: ModelListFilterTests.testChipsAppearWithTwoProvidersAndFilterToOne -->
  <!-- test: ModelListFilterTests.testASearchMatchesTheIdOrTheLineWithinTheFilter -->
  <!-- test: ModelListFilterTests.testASearchIsOfferedPastEightModels -->
  <!-- test: ModelListFilterTests.testThePanelIsSizedFromTheRoomThereIs -->
  <!-- test: ModelListFilterTests.testAtAnAccessibilitySizeTheListLeavesMoreAndKeepsNoChips -->
  <!-- test: RemainingScreensUITests.testTheModelListHoldsEveryProvidersModelsAndOneTapMovesTheChat -->
  <!-- test: QuickActionTests.testANewChatIsWithTheOpenConversationsProvider -->
  <!-- test: QuickActionTests.testANewChatIsWithTheFirstProviderWhenTheOpenOnesIsGone -->
  <!-- test: QuickActionTests.testANewChatIsWithTheMacWhoseChatIsOpen -->
  <!-- test: AppModelStreamingTests.testModelsAreListedAndAChoiceChangesOnlyTheConversation -->
  <!-- test: QuickActionTests.testAConversationMovedToAnotherProviderTakesItsDefaultModel -->
  <!-- test: QuickActionTests.testAConversationAHubIsStillWritingStaysOnItsProvider -->
  <!-- test: ConcurrentReplyTests.testAConversationWhoseReplyIsStreamingStaysOnItsProvider -->
- gglib draws pictures with an image model, and its model list names one
  with `image_generation`. Such a model cannot chat, and neither can one
  listed with `embeddings`: the model list offers neither, and a provider
  with no model chosen takes the first that can chat, not the first listed.
  Each of the eight codes gglib's drawing refuses with, and the one for a
  model chosen to draw with that is no image model, has a line of its own
  that says what happened to the picture and what to do, on a saved failure
  too; a picture that stalled, and an image model with no room while another
  reply is written, say to ask again and name no machine. The two codes a
  run can now end with, `model_unavailable` and `unavailable`, name a side.
  <!-- test: DrawingWireTests.testEachDrawingCodeSaysWhatToDo -->
  <!-- test: DrawingWireTests.testTheModelListSaysWhichModelDrawsAndWhichCanChat -->
  <!-- test: DrawingModelListTests.testTheModelListOffersOnlyModelsThatCanChat -->
  <!-- test: DrawingModelListTests.testTheDefaultModelIsTheFirstThatCanChat -->
- Whether a hub can draw is asked of it, `GET /v1/images/drawing`, and never
  guessed: when a chat opens on it and each time its pipe comes up, for a
  paired Mac and for no other server. gglib draws only for a device it has
  paired, so a gglib reached by its address is not asked, and a conversation
  on it has the switch dimmed, saying "Drawing needs a paired Mac." What it says is kept in memory: the image model when it can,
  and when it cannot, gglib's own reason, said as "home cannot draw: ...". A
  gglib from before drawing has no such route, and its 404 reads as a hub
  that cannot draw and needs updating. A hub not asked yet is not known to
  draw, an ask that fails keeps the answer before, and a removed provider
  takes its answer with it.
  <!-- test: DrawingWireTests.testAHubSaysWhetherItCanDrawAndAnOlderOneCannot -->
  <!-- test: DrawingAvailabilityTests.testAHubIsAskedWhetherItCanDrawAndItsAnswerIsTheReason -->
  <!-- test: DrawingAvailabilityTests.testAnAskThatFailsKeepsTheAnswerBefore -->
  <!-- test: DrawingAvailabilityTests.testOnlyGGLibIsAskedAndOfferedTheSwitch -->
  <!-- test: DrawingAvailabilityTests.testAMacsChatSaysWhyItsMacCannotDraw -->
- A newer gglib's answer about drawing lists its image models, `models`:
  each with its id on that machine, its name, its family, whether it has all
  its files and which it lacks, whether it is the default and whether it is
  loaded, in gglib's order. A family reads in gglib's words: Flux.1, SDXL,
  Qwen-Image 2.1 and Z-Image. A family or a role this build has not heard of
  is kept as the string it came as, and the answer still reads. An answer
  with no `models` is a gglib from before the list, which is never sent
  `image_model`; an empty list is a newer one with no image model. The
  question can name a model to be judged, `?image_model=<id>`. A message
  that draws names its image model beside `draw`: `image_model` in a Mac's
  turn, and `&image_model=<id>` in the query of a run for a conversation
  kept here. Neither says it without drawing, and with none chosen each is
  the request it was. gglib has recorded no such answer yet, so the fixture
  these read, `contract-images-drawing-models.json`, is the example in the
  contract both sides are built to and not a capture.
  <!-- test: ImageModelWireTests.testTheContractsAnswerListsTheImageModelsInOrder -->
  <!-- test: ImageModelWireTests.testAnAnswerWithoutTheListIsAnOlderGGLibAndAnEmptyListIsNot -->
  <!-- test: ImageModelWireTests.testAFamilyOrARoleThisBuildDoesNotKnowStillReads -->
  <!-- test: ImageModelWireTests.testEveryFamilyGGLibNamesReadsInItsWords -->
  <!-- test: ImageModelWireTests.testTheQuestionCanNameAnImageModelToBeJudged -->
  <!-- test: ImageModelWireTests.testATurnNamesItsImageModelOnlyWhenItDraws -->
  <!-- test: ImageModelWireTests.testARunNamesItsImageModelInItsQueryOnlyWhenItDraws -->
- A chat chooses the image model its pictures are drawn with, where its
  Mac lists two or more: the "Drawing with" line over the field, shown
  while Draw is on, is a menu of them, "Default (name)" first and then each
  in the Mac's order with its family, "loaded" for the one loaded now, and
  one that lacks a file dimmed with what it lacks. Picking one sets the
  choice and sends nothing; Draw itself is the switch and nothing more,
  and VoiceOver hears the line as "Image model" and the model's name. With
  one image model or none, and for a Mac from before the list, the line is
  plain and names the model.
  The choice is the chat's and is said with every message that draws, never
  with one that does not, and never to a Mac from before the list, which
  would refuse the word. A conversation kept here stores it in one optional
  column, a branch keeps it, and a provider moved to another Mac forgets it,
  since an id names a model on one machine. A Mac's chat holds it in memory
  with the chat open, and a chat opened again has none.
  <!-- test: ImageModelMenuTests.testTheMenuListsTheDefaultThenEachModelInTheOrderGiven -->
  <!-- test: ImageModelMenuTests.testThereIsAMenuOnlyWhereThereIsAChoice -->
  <!-- test: ImageModelMenuTests.testTheLineSaysWhichModelDrawsAndTheSwitchItsState -->
- A Mac that lists several image models that can draw and no default draws
  nothing until one is chosen, and the line over the field then asks which:
  Draw is not dimmed and turns over as ever, the line reads "Choose an
  image model" while it is on, and the list has no "Default" row, which
  would name nothing. Whether a Mac waits for a choice is read from its
  list, not from the words of its refusal. A model picked there can draw at
  once, by the list, before the Mac has answered about it. While Draw is
  on, the line names the image model the picture is drawn with, where one
  is known, in either kind of chat; and when the chat's choice is one the
  Mac cannot draw with, the line says "Cannot draw with" and the name
  whatever Draw shows, so another can be picked from it.
  <!-- test: ImageModelWireTests.testAHubAwaitsAChoiceWithSeveralCompleteModelsAndNoDefault -->
  <!-- test: ImageModelMenuTests.testWithNoDefaultTheMenuListsOnlyTheModelsAndTheLineAsksForOne -->
  <!-- test: HubChatImageModelTests.testAMacsChatWaitsForAChoiceThenNamesTheModelThatDraws -->
  <!-- test: ImageModelChoiceTests.testAnOlderMacHasNoMenuAndIsNeverSentAnImageModel -->
  <!-- test: ImageModelChoiceTests.testAChoiceIsSaidWithEachMessageThatDrawsAndNoOther -->
  <!-- test: ImageModelChoiceTests.testAModelWithoutItsFilesCannotBeChosen -->
  <!-- test: ImageModelChoiceTests.testAProviderMovedToAnotherMacForgetsTheChoice -->
  <!-- test: HubChatImageModelTests.testAnOlderMacHasNoMenuAndItsTurnNeverNamesAnImageModel -->
  <!-- test: HubChatImageModelTests.testAChoiceIsSaidWithEachTurnThatDrawsAndHeldOnlyWithTheChatOpen -->
  <!-- test: ImageModelStoreTests.testTheChoiceOutlivesAReopening -->
  <!-- test: ImageModelStoreTests.testAStoreOpensAcrossTheImageModelColumnInBothDirections -->
- A chosen image model the Mac cannot draw with is never swapped for
  another. The Mac is asked about a message that names the model chosen,
  when it is picked and each time it is asked about drawing, so a Mac with
  several image models and no default can draw once one is picked. A model
  the list no longer has, or has without a file, dims the switch with a
  sentence that says so, and the line over the field says so too and is
  still the menu to pick another from. A message
  the Mac refuses with `model_not_found`, `not_an_image_model` or
  `image_model_incomplete` keeps its refusal with the Mac's reason: a
  question kept here stays one that draws and Retry names the same model, a
  Mac's chat gets its draft back with Draw as it was, the choice is kept,
  and the Mac is asked again what it lists.
  <!-- test: ImageModelStaleTests.testAChoiceTheListNoLongerHasIsSaidAndNotSwapped -->
  <!-- test: ImageModelStaleTests.testARunRefusedForItsImageModelKeepsTheQuestionAndTheChoice -->
  <!-- test: ImageModelStaleTests.testTheMacIsAskedAboutTheModelChosen -->
  <!-- test: HubChatImageModelTests.testATurnRefusedForItsImageModelGivesTheDraftBackAndKeepsTheChoice -->
- A picture is asked for with a switch, never detected: Draw is pressed for
  one message, and it is the draft's, so the draft a send leaves has it off
  again. A turn to a Mac's chat says `draw: true` only for a message sent
  with it on to a Mac that said it can draw; any other turn is the body it
  always was, with no such key. A Mac that cannot draw, one from before
  drawing and one never heard from are sent the message without the word,
  since an older gglib refuses a key it does not know. A turn the Mac
  refuses gives its draft back with the switch as it was, and one put again
  says the same as the first time.
  <!-- test: DrawingWireTests.testATurnSaysDrawOnlyWhenItDraws -->
  <!-- test: HubChatDrawTests.testATurnSaysDrawOnlyWhenTheSwitchIsOn -->
  <!-- test: HubChatDrawTests.testAMacThatCannotDrawIsNeverSentTheWord -->
  <!-- test: HubChatDrawTests.testTheSwitchIsOffAgainOnceTheMessageIsSent -->
  <!-- test: HubChatDrawTests.testARefusedTurnKeepsItsSwitchAndALostOneIsPutAgainWithIt -->
- A Mac can refuse a turn after it has started the turn's run, since it now
  starts the run before it loads the model: the run ends failed with
  `model_unavailable`, `unavailable` or `conflict`, and no row saved. With
  nothing of a reply read, each is said as a refused turn is, with the
  code's own line when it has one, the run is no longer kept as one to read
  on, the Mac's rows are not read again, and the text and images go back
  into the composer, Draw as it was. `drawing_unavailable` and
  `image_model_cannot_chat` are answers to the `PUT`, before any run, and
  are taken the same way should a run ever end with one. A run that
  fails any other way, or after something of its reply came, ends as a
  reply that stopped.
  <!-- test: HubChatDrawTests.testARunThatEndsAsARefusalGivesTheDraftBack -->
- While a picture is drawn its run says how far it has got, and a reply held
  up behind one says what it waits for: gglib's `tool_progress` and `waiting`
  events, read as gglib records them, with the counts it reported and no
  others. A tool's end is read by its call's id, ahead of the images it
  made, and an image list that does not read still ends the call. A stage or
  a reason this build does not know means nothing, and the reply reads on.
  The reply holds the latest word in memory and nothing of it is kept: one
  line for it, "Drawing: step 12 of 20" in the locale's digits, with the
  picture's number from the second on and the place in line when it is not
  next; a tool's progress goes when its own call ends and not another's, a
  wait gives way to whatever comes next, and a run that ends leaves none.
  <!-- test: ToolProgressWireTests.testTheRecordedFramesOfAPictureReadAsItsWaitItsStagesAndItsEnd -->
  <!-- test: ToolProgressWireTests.testAWaitForAModelAndFramesThatDoNotReadMeanNothing -->
  <!-- test: ToolWorkTests.testEachStageOfAPictureHasItsLine -->
  <!-- test: ToolWorkTests.testAWaitSaysWhatIsInTheWay -->
  <!-- test: ToolWorkTests.testTheLatestWordIsShownUntilItsToolEnds -->
  <!-- test: ToolWorkTests.testAMacsReplyShowsTheWorkItsRunReportsUntilTheRunEnds -->
- The look at a picture being drawn travels beside its run's numbered events
  and is not one of them: gglib's `event: preview`, a small PNG with no
  `id:`. A run's reader reads it by its name, ahead of the numbering, so one
  with no id is not dropped as a frame already read, and one with an id
  moves no cursor past the frames that follow; one whose bytes are not
  base64, or whose frame is missing, is passed over. A Mac's reply holds
  only the latest look, in memory: its cursor stays at the last frame, so
  reading on asks from there, and the look goes when its own tool's call
  ends, not another's, and when the run ends.
  <!-- test: PreviewWireTests.testAPreviewIsReadAheadOfTheNumberingAndMovesNoCursor -->
  <!-- test: PreviewWireTests.testAPreviewThatDoesNotReadIsPassedOver -->
  <!-- test: DrawingPreviewTests.testOnlyTheLatestLookIsHeldAndItGoesWithItsTool -->
  <!-- test: DrawingPreviewTests.testAMacsReplyShowsTheLookAndItsCursorDoesNotMove -->
  <!-- test: DrawingPreviewTests.testARunThatEndsMidPictureLeavesNoLook -->
- A conversation kept on this device draws too, and runs a paired Mac's
  tools. A message sent with Draw on, to a hub that said it can draw, is
  put as `PUT /v1/runs/{id}?kind=chat&tools=none&draw=true` when it names
  no server, which leaves it gglib's drawing tool alone, or with the
  servers' ids in place of `none`; a hub that cannot draw, is too old or
  was never heard from is sent it as one that does not draw. A paired Mac
  whose answer about drawing names MCP servers it offers (`mcp_servers`,
  each by its id on the Mac and its name, two of one name read as two,
  said whether or not it can draw) has every question, drawing or not,
  put naming the servers its conversation picked that the Mac still
  offers, by id, sorted and joined by a bare comma, as
  `PUT /v1/runs/{id}?kind=chat&tools=3,7`, Retry included, so its reply
  can call their tools; gglib starts only those of them it opens to
  devices. A new conversation picks none, so its questions are plain runs
  until a server is picked, and a pick made while a reply is being written
  reaches the next request, not that run. A pick the Mac stops offering is
  kept and not named. The body is the OpenAI request it always was. Any
  other message has no query at all unless it draws: one with no server
  picked, one to a Mac that names no server or to a gglib from before the
  list, and one to a gglib reached by address, which refuses the words.
  A Mac not heard from yet, after a relaunch or an edit, is named every
  pick as kept, a fresh send and a question put again alike, and drops
  any it no longer opens; such a run takes one of the Mac's agent slots
  while the wrench is hidden. A question whose answer was lost is sent
  again under its id with the conversation's picks as they are then;
  gglib keeps a started run's tools. A Continue is sent again as a
  Continue, with none and not drawing, a reply that has only thought or
  holds only a picture included, so no second picture is drawn.
  The Draw switch is off again in the draft a taken send leaves, and a refused
  draft keeps it. The run's answer says how its events are written, `frames`,
  and that picks the decoder: `agent` is read as a Mac's chat's run is, and
  absent is the chat route's chunks, as every run before. The question is
  kept as one that drew, so Retry asks for the picture again while the hub
  can draw and goes without once it cannot; Continue, which carries a
  reply's words on, never asks for a picture or runs tools. A
  run that ends with one of drawing's codes leaves it on the question with
  the code's own line, unless the run reported an error of its own first:
  then that sentence is what the question shows, with no code and no line
  under it. A question the hub refused to draw for, with
  `drawing_unavailable` on the `PUT` or at the run's end, stops asking. A
  run whose answer names a way of writing its events this build does not
  know still reads as a run, is stopped, and is given up with a sentence;
  a list that holds one still reads the others. What a Mac said of drawing
  is forgotten when its provider is moved to another Mac.
  <!-- test: DrawingRunWireTests.testARunThatDrawsIsPutWithItsQueryAndTheBodyUnchanged -->
  <!-- test: DrawingRunWireTests.testARunsReportSaysHowItsFramesAreWritten -->
  <!-- test: DrawingRunWireTests.testTheFramesPickTheDecoder -->
  <!-- test: DrawingRunTests.testAMessageSentWithDrawStartsARunThatDraws -->
  <!-- test: DrawingRunTests.testAHubThatCannotDrawIsSentAPlainRun -->
  <!-- test: DrawingRunTests.testTheSwitchIsOffAgainOnceTheMessageIsSent -->
  <!-- test: DrawingRunTests.testTheRunsAnswerSaysHowItsEventsAreRead -->
  <!-- test: DrawingRunTests.testRetryAsksForThePictureAgainWhileTheHubCanDraw -->
  <!-- test: DrawingRunTests.testARunsOwnErrorIsWhatTheQuestionShows -->
  <!-- test: DrawingRunTests.testContinueNeverAsksForAPicture -->
  <!-- test: DrawingRunTests.testAQuestionAHubRefusedToDrawForStopsAsking -->
  <!-- test: DrawingRunTests.testAProviderMovedToAnotherMacForgetsWhetherItCanDraw -->
  <!-- test: DrawingRunTests.testARunWrittenAWayThisBuildCannotReadIsGivenUp -->
  <!-- test: DrawingRunWireTests.testAnUnknownWordForTheFramesStillReads -->
  <!-- test: ToolsOfferedWireTests.testAnAnswerThatNamesServersOffersToolsWhetherOrNotItCanDraw -->
  <!-- test: ToolsOfferedWireTests.testTwoServersOfOneNameAreReadAsTwo -->
  <!-- test: ToolsOfferedWireTests.testARunWithToolsIsPutWithThemAndDrawsOnlyWhenItDraws -->
  <!-- test: ToolChoiceRunTests.testANewChatAsksAPlainRunAndAPickedServerIsPutByID -->
  <!-- test: ToolChoiceRunTests.testAMacThatCannotDrawStillSendsThePicks -->
  <!-- test: ToolChoiceRunTests.testAMacThatNamesNoServersIsSentNoneOfThePicks -->
  <!-- test: ToolChoiceRunTests.testRetryNamesThePicksAndContinueDoesNot -->
  <!-- test: ToolChoiceRunTests.testAGglibByAddressIsNeverSentAServer -->
  <!-- test: ToolChoiceRunTests.testAQuestionPutAgainAfterItsAnswerWasLostCarriesThePicks -->
  <!-- test: ToolChoiceRunTests.testAContinuePutAgainAfterItsAnswerWasLostRunsNoTools -->
  <!-- test: ToolChoiceRunTests.testAContinueOfAReplyThatOnlyThoughtIsPutAgainAsAContinue -->
  <!-- test: DrawingRunImageTests.testAContinueOfAReplyOfAPictureAloneIsPutAgainAsAContinue -->
  <!-- test: ToolChoiceRunTests.testAServerTheMacClosedIsNotNamed -->
  <!-- test: ToolChoiceRunTests.testADrawQuestionWithNoPicksIsPutWithNone -->
  <!-- test: ToolChoiceRunTests.testAPickMadeDuringARunReachesOnlyTheNextRequest -->
  <!-- test: ToolChoiceRunTests.testAFreshSendToAnUnheardMacNamesThePicksAsKept -->
  <!-- test: ToolChoiceTests.testANewChoiceNamesNoServer -->
  <!-- test: ToolChoiceTests.testPicksAreNamedOnlyWhileTheMacOffersThem -->
  <!-- test: ToolChoiceTests.testAnUnheardMacIsNamedThePicksAsKept -->
  <!-- test: ToolChoiceTests.testAPickSurvivesARename -->
- A conversation kept here on a paired Mac that offers its MCP servers'
  tools has a wrench in its top bar that opens a menu: "Use tools", the
  conversation's master switch, on for a new conversation, then under
  "Servers" a tick for each server the Mac offers, in the Mac's order,
  none ticked until one is picked; while the switch is off every row is
  still there with its pick, and none is named. Two servers of one name
  each show their id after it,
  `fs (3)`. The wrench's name says its state in words, "Tools, off",
  "Tools, none picked", "Tools, 1 server" or "Tools, 2 servers", so the
  state is never the tint alone, and it is filled only while a server
  would be named. On an iPhone the menu stays open while picks are made;
  on a Mac it closes after each. While the Mac offers a server the
  conversation has never shown, a new conversation's included, the wrench
  carries the system's "!" badge, its name ends ", new tools available",
  since the badge is not read, and the server's row says "New"; a server
  the Mac opens later badges every conversation and is picked in none. A
  change made from the menu shows every server offered, in the same write,
  and clears the badge; opening the menu and closing it with nothing
  changed leaves it, as a SwiftUI menu says nothing of being opened. On an
  open iPhone Duo on its side the panel's button carries the badge and its
  name says so too, and the panel's tools rows coming on screen, or the
  Mac's offer changing while they are, show the servers, which say "New"
  for as long as the rows stay. A branch keeps what its conversation has
  shown. Off, a question is put as a plain run,
  with no query, and one sent with Draw is put as
  `PUT /v1/runs/{id}?kind=chat&tools=none&draw=true`, with the chosen
  image model after it, which leaves it gglib's drawing tool and no other;
  the picks are kept, and turning the switch on again names them again.
  The body is the one it always was. The choice is the conversation's,
  by the servers' ids on the Mac so a rename keeps a pick, kept in one
  optional column written only for a choice that is not a new
  conversation's, every key written, and outlives a relaunch; a pick or
  the switch leaves the conversation's date alone, and a press that
  changes nothing writes nothing. A branch copies it, and a move to
  another provider, or an edit that points the provider at another Mac,
  re-pairing included, drops it, as an id names a server on one Mac
  alone. Picks are never pruned, since a Mac that answers with none may
  have failed to read its own list. A gglib reached by address, a Mac
  that names no servers, one from before the list and one not heard from
  have no wrench, and a Mac's own chat keeps its tools on the Mac
  ([ADR 0014](adr/0014-each-conversation-picks-which-of-the-macs-servers-it-uses.md)).
  Which servers the Mac offers is chosen on the Mac: the server-status
  sheet lists them by the names the Mac gives them, one row for each
  server even when two share a name, under "Tools offered", with a line
  saying a server is opened on the Mac with
  `gglib mcp allow-remote <server>` and that each conversation picks the
  ones it uses from its Tools control, and nothing there can be tapped.
  The section is not there where no tools are offered.
  <!-- test: ToolsOfferedWireTests.testARunWithToolsIsPutWithThemAndDrawsOnlyWhenItDraws -->
  <!-- test: AppModelToolsTests.testANewConversationIsOnWithNoServerPickedAndTheSwitchTurnsItOff -->
  <!-- test: AppModelToolsTests.testOffSendsAPlainRunAndWithDrawOnlyTheDrawingToolAndKeepsThePicks -->
  <!-- test: AppModelToolsTests.testAQuestionPutAgainAfterItsAnswerWasLostKeepsTheToolsOff -->
  <!-- test: AppModelToolsTests.testTheMenuIsHiddenWhereNoServerIsOfferedAndAnUnheardMacIsSentThePicksAsKept -->
  <!-- test: AppModelToolsTests.testARelaunchedPutBeforeTheMacsAnswerNamesThePicksAsKept -->
  <!-- test: ToolChoiceTests.testTurnedOffNamesNoneAndKeepsThePicks -->
  <!-- test: ToolChoiceTests.testSeenOutlivesAServerTheMacClosed -->
  <!-- test: ToolChoiceTests.testItEncodesEveryKeySorted -->
  <!-- test: ToolsMenuTests.testHiddenWhereTheMacOffersNone -->
  <!-- test: ToolsMenuTests.testHiddenOnAMacsChatAndByAddress -->
  <!-- test: ToolsMenuTests.testRowsAreTheMacsServersInItsOrder -->
  <!-- test: ToolsMenuTests.testASharedNameShowsEachServersID -->
  <!-- test: ToolsMenuTests.testLabelsAndSymbols -->
  <!-- test: ToolsMenuTests.testOffKeepsEveryRowAndItsPickAndNamesNone -->
  <!-- test: ToolsMenuTests.testPickingLeavesUpdatedAtAlone -->
  <!-- test: ToolsMenuTests.testAPressThatChangesNothingWritesNothing -->
  <!-- test: ToolsSeenTests.testANewChatIsBadgedAndPicksNone -->
  <!-- test: ToolsSeenTests.testAChangeFromTheMenuClearsTheBadge -->
  <!-- test: ToolsSeenTests.testMarkingSeenTwiceWritesOnce -->
  <!-- test: ToolsSeenTests.testAServerTheMacOpensLaterIsBadgedInEveryChatAndUnpicked -->
  <!-- test: ToolsSeenTests.testABranchIsNotBadgedForWhatItsSourceSaw -->
  <!-- test: ToolChoiceTests.testUnseenIsWhatTheMacOffersThatThisChatNeverShowed -->
  <!-- test: BookPagesTests.testTheThisChatButtonSaysNewToolsAreAvailable -->
  <!-- test: ToolChoiceStoreTests.testTheToolChoiceOutlivesAReopeningAndAnUnchangedOneMarksNoRow -->
  <!-- test: ToolChoiceStoreTests.testANonDefaultChoiceRoundTripsEveryKey -->
  <!-- test: ToolChoiceStoreTests.testAStoreOpensAcrossTheToolChoiceColumnInBothDirections -->
  <!-- test: ToolChoiceRunTests.testEditingAProviderToAnotherMacForgetsItsChoices -->
  <!-- test: ProxyStatusToolsTests.testTheSheetListsTheServersAMacOffersAndNothingWhereNoneAre -->
  <!-- test: ConversationBranchesTests.testABranchCopiesTheSettingsAndNoRun -->
  <!-- test: QuickActionTests.testAConversationMovedToAnotherProviderTakesItsDefaultModel -->
- A conversation kept here remembers how its picture was made. The reply a
  run drew for keeps, with its words and its picture, each tool the run
  called and what the tool answered: the call's id, the tool's name, the
  arguments the model wrote as JSON text, the answer word for word, the MCP
  server the tool is one of when `tool_call_start` names one (`server`,
  which gglib leaves out for its own tools), whether the tool failed, the
  opposite of `result.success`, and the ids of the images it made, from
  `result.images`, none for a call that made none, read from the run's
  `tool_call_start` and `tool_call_complete` events and kept in one
  optional column. An answer that does not say is not known to have failed
  or worked. A list kept before the images were read does not read, and
  the reply loads with no calls: its words and pictures stay, but it draws
  no tool rows, sends no calls again, shows its picture to no model and
  offers no fix or redo. Its column is left as it was only until the reply
  is written again: a Continue, or a reading on of a reply still being
  written when this build came, writes over it the calls the reply has
  then, so the old ones are gone for good, and a call begun before and
  answered after keeps neither its answer nor its images.
  The transcript holds the messages it always did, and each call is drawn
  under its reply as a collapsed row, as the item after next says.
  Every later request says it again ahead of the reply's words, in OpenAI's
  shape: an assistant message with the call in `tool_calls` and no content,
  then a `tool` message with the call's id and the answer. The server and
  the failure are never sent, nor the images a call made: the request is
  byte for byte the one it would be without them. gglib reads that as a
  chat that holds a drawn picture and tells the model so, which is what
  stops the next reply saying it cannot
  make images (gglib issue 1387). Only gglib is sent them, a paired Mac or
  one reached by an address that answered as gglib; any other server is
  sent the reply's words alone, as before, since some refuse a tool message
  in a request that offers no tools. A call nothing answered is left out, a
  reply of a picture alone sends no empty words, and a draw that failed is
  sent with the tool's own error when its reply was kept. The picture
  itself goes only to a model that reads images, as the next item says. A
  reply from before this keeps no call and is sent as it was, a branch's
  copy keeps its calls, an answer read by a later reading of the run finds
  its call, and a store opens across the column in both directions.
  <!-- test: DrawnHistoryWireTests.testTheRecordedFramesOfAPictureLeaveItsCallAndItsAnswer -->
  <!-- test: DrawnHistoryWireTests.testTheMessageAfterAPictureCarriesTheCallItsAnswerThenTheWords -->
  <!-- test: DrawnHistoryWireTests.testAnotherServerAndAReplyFromBeforeAreSentTheWordsAlone -->
  <!-- test: DrawnHistoryWireTests.testTwoPicturesAreTwoCallsEachAnsweredUnderItsOwnID -->
  <!-- test: DrawnHistoryWireTests.testACallNothingAnsweredIsLeftOutAndAPictureAloneSendsNoEmptyWords -->
  <!-- test: DrawnHistoryWireTests.testACallsArgumentsAreJSONTextAndAnAnswerGoesOnItsOwnCall -->
  <!-- test: DrawnHistoryWireTests.testABranchKeepsAReplysCallsAndTheRowsAreUnchanged -->
  <!-- test: DrawnHistoryTests.testAReplyKeepsHowItsPictureWasMadeAndTheNextRequestCarriesIt -->
  <!-- test: DrawnHistoryTests.testOnlyGglibIsSentTheCalls -->
  <!-- test: DrawnHistoryTests.testTwoPicturesKeepTwoCallsUnderTheirOwnIDs -->
  <!-- test: DrawnHistoryTests.testAnAnswerReadOnALaterReadingFindsItsCall -->
  <!-- test: DrawnHistoryTests.testTheCallsOutliveAReopening -->
  <!-- test: ToolExchangeWireTests.testANilServerAndFailureAreLeftOutAndReadBack -->
  <!-- test: ToolExchangeWireTests.testAToolsServerAndItsFailureLandOnItsExchange -->
  <!-- test: ToolExchangeWireTests.testTheRequestNeverSaysAToolsServerOrWhetherItFailed -->
  <!-- test: ToolExchangeWireTests.testEachAnsweredCallKeepsTheImagesItMade -->
  <!-- test: ToolExchangeWireTests.testAListKeptBeforeTheImagesDoesNotRead -->
  <!-- test: DrawnHistoryTests.testAStoreOpensAcrossTheCallsColumnInBothDirections -->
- A model that reads images is shown the most recent picture drawn in a
  conversation kept here, as gglib asks of a client that keeps its own
  chats (gglib's `docs/clients.md`, Images): gglib cannot read this
  device's pictures, so this device sends it. The first message the person
  sent after the draw goes as three kinds of part, in this order: gglib's
  line saying the image was added automatically and is the drawing tool's
  most recent picture, the picture as a base64 `data:` URL read from this
  device's store, then the message's own words and images. Only the newest
  picture is shown: the last image of the latest reply that holds an
  answered call of the drawing tool that no other tool of that reply made,
  so a fix kept on the reply takes the place of the picture it came from,
  and a newer drawing moves it to the message after that one, which leaves
  the older message as it was written. A reply's images are every tool's,
  and each answered call keeps the ids of the ones it made, so with a Mac
  that offers its MCP servers' tools a reply that both drew and, say,
  searched or drew a chart shows its drawn picture: a search made no image
  and hides nothing, and a chart's image is passed over though it came
  last. A fix or a redo is no call's, so it is still shown. A reply whose
  every image another tool made drew none, and the picture before it is
  shown. Every later request carries the picture on the same message. It
  goes only to gglib, which is sent the draw's call and answer, and only
  for a model whose entry in gglib's model list says `vision`; any other
  model, and one the list does not name, is sent the chat as before, with
  no picture and no bytes read. A picture whose bytes this device no
  longer has is left out rather than stopping the message, and nothing of
  it is saved.
  <!-- test: DrawnPictureShownWireTests.testTheMessageAfterADrawCarriesTheLineThePictureThenItsOwnParts -->
  <!-- test: DrawnPictureShownWireTests.testOnlyTheNewestPictureIsShown -->
  <!-- test: DrawnPictureShownWireTests.testTheSameMessageCarriesItOnEveryLaterRequest -->
  <!-- test: DrawnPictureShownWireTests.testANewerPictureMovesToTheMessageAfterIt -->
  <!-- test: DrawnPictureShownWireTests.testNoDrawnPictureNoPicture -->
  <!-- test: DrawnPictureShownWireTests.testAReplyThatDrewAndCalledAnotherToolShowsTheDrawnPicture -->
  <!-- test: DrawnPictureShownWireTests.testAFailedDrawBesideAnotherToolsImageShowsNoPicture -->
  <!-- test: DrawnPictureShownTests.testAModelThatReadsImagesIsShownTheDrawnPicture -->
  <!-- test: DrawnPictureShownTests.testAModelThatDoesNotListVisionIsNotShownIt -->
  <!-- test: DrawnPictureShownTests.testAServerThatIsNotGglibIsNotShownIt -->
  <!-- test: DrawnPictureShownTests.testAPictureWhoseBytesAreGoneIsLeftOut -->
  <!-- test: DrawnPictureBesideAnotherToolWireTests.testADrawBesideASearchThatMadeNoImageIsShown -->
  <!-- test: DrawnPictureBesideAnotherToolWireTests.testAnotherToolsImageIsPassedOverAndAKeptFixIsStillShown -->
  <!-- test: DrawnPictureBesideAnotherToolWireTests.testAReplyWhoseEveryImageAnotherToolMadeShowsThePictureBefore -->
  <!-- test: DrawnPictureShownTests.testAReplyThatDrewAndSearchedShowsItsDrawnPicture -->
- Under a finished reply kept here, each tool it called is one row,
  collapsed, in the order it called them: a wrench, the tool's name after
  its first `:`, then whose it is, the MCP server the call named or
  "gglib" for one of gglib's own (`builtin:…`), as in
  `tavily_search · Tavily Web Search`. A tool whose owner is not known
  shows its name alone. A tool that said it failed has a warning mark, and
  VoiceOver hears "failed" in the row's name, so it is never the colour
  alone. Opened, the row shows what was Sent, the arguments as JSON laid
  out over lines with their keys sorted, or as written when they are not
  JSON, and what was Received, the answer as the tool gave it, cut after
  2,000 characters and never inside one, with a line saying how many more
  in the locale's digits. A call nothing answered says it was not
  answered. Both can be selected. It is the same for every tool. A
  question has no rows, and nor has a reply still being written, here or
  on the Mac: one written here shows its tool lines as it did, and the
  rows come once it has finished.
  <!-- test: ToolExchangeDisplayTests.testAHeadingNamesTheToolAndWhoseItIs -->
  <!-- test: ToolExchangeDisplayTests.testTheArgumentsAreLaidOutWhenTheyAreJSON -->
  <!-- test: ToolExchangeDisplayTests.testALongAnswerIsCutOnACharacterAndSaysHowMuchMore -->
  <!-- test: ToolExchangeDisplayTests.testACallNothingAnsweredHasNoAnswerToShow -->
  <!-- test: ToolCallRowTests.testTheRowSaysTheToolWhoseItIsAndWhetherItFailed -->
  <!-- test: ToolCallRowTests.testEachToolAStoredReplyCalledIsOneRowAndAQuestionHasNone -->
- The picture such a run draws is this device's to keep, since the
  conversation is: its bytes are read from the hub by id as soon as the tool
  finishes, before its frame is applied, checked against the id, kept in
  this device's store under the same SHA-256 a question's image has, and
  named by the reply's message, with words or without. One already kept is
  not read again. One lost on the way is not passed over: the reply walks
  away with its cursor at the frame before, and the next reading asks again.
  One the hub no longer has, or whose bytes are not its id's, is named and
  not kept. A reply's picture is not sent back as the reply's own, so a
  request needs its bytes only to show it to a model that reads images, as
  the item above says. While it is drawn the reply shows its step and the
  latest look, and keeps neither. The background walks away with the run's
  id, its cursor and how it writes its events, kept with the message in two
  optional columns that a store opens across both ways, and coming back
  reads on with the same decoder.
  <!-- test: DrawingRunWireTests.testAReplysImagesAreNotSentBackToTheModel -->
  <!-- test: DrawingRunImageTests.testAPictureIsReadOnceAndKeptUnderItsID -->
  <!-- test: DrawingRunImageTests.testAPictureLostOnTheWayIsAskedForAgain -->
  <!-- test: DrawingRunImageTests.testAPictureTheHubDoesNotHaveIsNamedAndNotKept -->
  <!-- test: DrawingRunImageTests.testAReplyReadOnIsReadAsItsRunWritesIt -->
  <!-- test: DrawingRunImageTests.testAReplyOfAPictureAloneIsKept -->
  <!-- test: DrawingStoreTests.testThatAQuestionDrewAndHowItsRunWritesOutliveAReopening -->
  <!-- test: DrawingStoreTests.testAStoreOpensAcrossTheDrawingColumnsInBothDirections -->
- Both composers have a Draw switch, the local one only where the provider
  is gglib, and dimmed there unless it is a paired Mac. Its state is never colour alone: the brush is
  filled while on and an outline while off, with "On" or "Off" to hear. A
  hub that cannot draw dims it and keeps it showing off, VoiceOver hears
  "Unavailable" and the reason, and a press says the reason and turns
  nothing on. While a picture is drawn or waited for, a reply shows the
  line for it in the spinner's place, or under its words when it has some,
  with a bar while the steps are counted and the latest look at the
  picture, drawn from the frame as it came and scaled up smoothly; bytes
  that are not a picture draw nothing. A reply kept on this device also
  shows a line for each tool it calls, and under it the pictures made, read
  from this device's store. While the model is still writing a call, a
  reply here and one on a Mac's chat show one line for it, such as
  “Writing Generate Image… 512 tokens” with the count in the locale's
  digits, from gglib's `tool_call_writing`; each later count, and then the
  call's own line, takes its place. When a run ends with such a line still
  showing, cut off or failed, the line goes with it: an ended reply shows no
  call still being written.
  <!-- test: DrawingViewTests.testTheDrawSwitchSaysItsStateAndAPressSaysWhyItCannotDraw -->
  <!-- test: DrawingViewTests.testAMacsReplyDrawsTheWorkInPlaceOfTheSpinner -->
  <!-- test: DrawingViewTests.testTheWorkIsItsLineItsBarAndTheLatestLook -->
  <!-- test: DrawingViewTests.testAReplyKeptHereShowsItsToolsAndNoSpinnerWhileAPictureIsDrawn -->
  <!-- test: ToolCallWritingWireTests.testACallBeingWrittenIsALineWithItsCountOnBothDoors -->
  <!-- test: HubChatContinueTests.testARunThatEndsWhileACallIsWrittenLeavesNoWritingLine -->
  <!-- test: ToolCallWritingWireTests.testTheCountIsInTheLocalesDigitsAndAFrameWithoutANameIsNothing -->
  <!-- test: ToolLinesTests.testACallBeingWrittenIsOneLineThatItsCallTakesThePlaceOf -->
- Draw can be pressed for a second message in the same chat. A press that
  changes nothing of a draft but the switch is a change to it, which is
  what SwiftUI asks of a composer's draft before it draws the composer
  again; a composer holding only the switch is still an empty one. Once a
  reply with a picture has ended nothing refuses Draw, and the second
  picture's steps and the looks at it reach its reply as the first's did,
  read from the start of its own run, in a conversation kept here and in a
  Mac's chat.
  <!-- test: DrawAgainTests.testAPressOfDrawAloneIsAChangeToTheDraft -->
  <!-- test: DrawAgainTests.testAConversationHereDrawsASecondTime -->
  <!-- test: DrawAgainTests.testAMacsChatDrawsASecondTime -->
- A picture the drawing tool made can be drawn again from itself. gglib's
  `POST /v1/images/generations` is sent the picture's own bytes as base64, the
  words without the space around them, a strength, `stream`, a `mask` only
  when a part is to change, and the image model's id as text only when one is
  chosen. A mask is a PNG the picture's exact size in pixels with no alpha:
  black wherever nothing was brushed, white under a stroke, black again under
  a later stroke that rubs out, a dot for a touch that never moved, and the
  strokes placed from the picture's top left. A pointer on screen is a point
  in the picture's own pixels, held inside the picture. The stream is read as
  its progress (the stage, the step, the place in line and the latest look),
  then the first picture, where the reading stops; an `error` event and an
  answer that is not a 2xx are said in the Mac's own words, and a stream that
  ends with neither says "The render ended without a picture." Each stage has
  its sentence, in the locale's digits. A reader that leaves closes the
  request, which is what stops the render. A picture is kept in a Mac's chat with
  `POST /v1/chats/{id}/pictures` and the two ids, `from` and `image`. gglib
  has recorded none of these bodies, so the tests are written from the
  contract both sides are built to.
  <!-- test: PictureRedrawWireTests.testAFixSendsThePictureItsMaskItsStrengthAndItsModelAsText -->
  <!-- test: PictureRedrawWireTests.testARedoSendsNoMaskAndTheMacsOwnChoiceNoModel -->
  <!-- test: PictureRedrawWireTests.testTheStreamIsReadAsItsProgressThenTheFirstPicture -->
  <!-- test: PictureRedrawWireTests.testAnErrorEventAndARefusalAreSaidInTheMacsWords -->
  <!-- test: PictureRedrawWireTests.testAStreamThatEndsWithoutAPictureFails -->
  <!-- test: PictureRedrawWireTests.testEachStageOfARedrawHasItsSentence -->
  <!-- test: PictureRedrawWireTests.testAReaderThatLeavesClosesTheRequest -->
  <!-- test: PictureRedrawWireTests.testAPictureIsKeptByItsTwoIDsAndARefusalIsTheMacsError -->
  <!-- test: PictureRedrawWireTests.testAPointerIsPlacedInThePicturesPixelsAndHeldInside -->
  <!-- test: PictureRedrawWireTests.testOnlyAStrokeThatPaintsMarksSomething -->
  <!-- test: PictureMaskTests.testTheMaskIsThePicturesSizeAndOpaqueBlackWhereNothingWasBrushed -->
  <!-- test: PictureMaskTests.testAStrokeIsWhiteWhereItWentFromTheTopLeft -->
  <!-- test: PictureMaskTests.testALaterRubOutIsBlackAgainAndAnEarlierOneIsNot -->
  <!-- test: PictureMaskTests.testASinglePointPaintsADot -->
  <!-- test: PictureMaskTests.testThePictureIsFittedToItsSpaceInTheMiddle -->
- Opened whole, a picture the drawing tool made has Fix or redo under it.
  Fix a part: the part brushed over is drawn again, with a brush size, Rub
  out, Undo and Clear. Redo the whole picture: all of it is drawn again from
  itself. Both start from the words the picture was drawn from, with a
  strength from "Change it a little" to "a lot" that starts at 0.75 for a fix
  and 0.4 for a redo. The button is dimmed, with the reason written beside
  it, until a fix has a stroke that paints and either has words. While the
  Mac draws, the stage is said, the latest look lies over the picture, a
  report with no look keeps the one before, and Stop ends the render, as
  leaving the editor does; what a stopped render or one another replaced
  says afterwards changes nothing. A failure says the Mac's words and can be
  asked again. The result is shown with a control that shows the original
  while held, which VoiceOver turns over with a press, and Keep, Try again
  and Discard; until Keep nothing is sent to the Mac's store or its chat and
  nothing is written here. While a render, a result or a Keep is in hand the
  sheet cannot be swiped away and has no way back. The original is no longer
  held up once the redraw moves on, and an iPhone or iPad is kept from
  locking for as long as a render is under way, however it ends. The editor
  holds the picture's bytes from the moment it opens, and the mask is the
  size those bytes decode to, whatever the picture's reference says. The Mac
  is looked up each time it is asked, so an editor left open across a pipe
  hung up and dialled again draws and keeps through the new one, and says
  the Mac is unreachable in between without losing the picture. The image
  opened whole and its editor are held by the app and shown from its root,
  so a chat whose rows are drawn again under the sheet takes nothing with
  them.
- On iOS 27.1 the editor arranges the picture and its controls around the
  screen: side by side while the editor is wider than tall, the picture above
  the controls while it is taller, and on a half-open iPhone Duo each on its
  own side of the fold, with the controls scrolling within their half. On a
  Mac, and on iOS before 27.1, the editor is the one scrolling column it was.
  <!-- test: PictureEditingTests.testFixWaitsForABrushStrokeAndBothWaitForWords -->
  <!-- test: PictureEditingTests.testAFixSendsThePictureWithAMaskItsSizeAndARedoSendsNoMask -->
  <!-- test: PictureEditingTests.testARenderIsFollowedToItsPictureAndAFrameIsKeptAcrossAReportWithoutOne -->
  <!-- test: PictureEditingTests.testAFailureSaysTheMacsWordsAndCanBeAskedAgain -->
  <!-- test: PictureEditingTests.testStopAndLeavingEndTheRenderAndALateEventChangesNothing -->
  <!-- test: PictureEditingTests.testARenderAnotherReplacedIsIgnored -->
  <!-- test: PictureEditingTests.testNothingIsStoredOrLinkedByDrawingDiscardTryAgainOrStop -->
  <!-- test: PictureEditorLifeTests.testTheMacIsLookedUpWhenItIsAskedNotWhenTheEditorOpens -->
  <!-- test: PictureEditorLifeTests.testAPipeHungUpAndDialledAgainLosesNoPicture -->
  <!-- test: PictureEditorLifeTests.testTheMaskIsTheSizeOfThePicturesBytesWhichAreHeldFromOpening -->
  <!-- test: PictureEditorLifeTests.testTheEditorIsTheModelsAndOutlivesTheRowThatOpenedIt -->
- Keep puts the newer picture in the chat after the one it came from, and
  the editor closes. In a Mac's chat it is sent to the Mac as a turn's image
  is, `POST /v1/attachments`, then named with the picture it came from to
  `POST /v1/chats/{id}/pictures`; the chat is read again and shows it last
  on that reply, drawn from the bytes this phone already holds, and nothing
  of it is written here (ADR 0007). A read that fails after the Mac kept it
  is not a failed Keep. In a conversation kept here its bytes go into this
  device's store and its name onto the same reply, after the pictures the
  reply has. A Keep that fails leaves the drawn picture where it was, under
  "The picture was drawn but could not be kept: ..." with the reason, and
  Keep can be pressed again; a picture the Mac already stored is not sent a
  second time. The image model starts at the one the chat already draws
  with, and at the Mac's own when the chat chose none or the Mac lists the
  choice without its files, with a menu only where the Mac lists two or more
  that can draw; a Mac that cannot draw until a model is named, and lists
  exactly one that can, starts at that one; one that lists several and has
  no default is asked for a model before anything is drawn. Fix or redo is
  offered only on a
  PNG. In a Mac's chat it is one on the row of a `builtin:generate_image`
  call that has a `prompt`, so a person's own image and another tool's have
  none. In a conversation kept here it is any PNG on a reply that holds
  exactly one such call that drew, but not one another call of that reply
  made, such as a chart: its fix would be kept as no call's and shown to a
  model as the drawn picture. A reply with two drawing calls has none,
  since which made which picture is not read, and a question's image has
  none. No
  picture has it while its Mac is out of reach, is reached by its address,
  or has nothing to draw with.
  <!-- test: PictureKeepingTests.testKeepStoresThePictureThenLinksItAndTheChatShowsItLast -->
  <!-- test: PictureKeepingTests.testAFailedKeepLeavesThePictureAndKeepWorksASecondTime -->
  <!-- test: PictureKeepingTests.testAReadThatFailsAfterAKeepIsNotAFailedKeep -->
  <!-- test: PictureKeepingTests.testTheImageModelStartsAtTheChatsOwnChoice -->
  <!-- test: PictureKeepingTests.testAMacWithNoDefaultIsAskedWhichImageModelFirst -->
  <!-- test: PictureKeepingTests.testOnlyAPictureTheDrawingToolMadeOnAMacThatCanDrawIsOffered -->
  <!-- test: PictureKeptHereTests.testAConversationHereKeepsTheNewerPictureOnItsReply -->
  <!-- test: PictureKeptHereTests.testAConversationHereStartsAtItsOwnImageModel -->
  <!-- test: PictureKeptHereTests.testOnlyAReplysDrawnPictureIsOfferedInAConversationKeptHere -->
  <!-- test: PictureKeptHereTests.testAnotherToolsPictureOnAReplyThatDrewIsNotOffered -->
  <!-- test: PictureRedrawWireTests.testADrawnPicturesWordsAreItsToolCallsPrompt -->
  <!-- test: PictureRedrawWireTests.testAKeptReplyKnowsItsPicturesWordsFromTheOneCallThatDrew -->
- A pairing string is read by modelpipe as it is typed and as it is scanned,
  against `docs/pairing-v0.md`'s normative vectors: the ticket comes back in
  its canonical lower-case form, so a QR scan and a paste of the same machine
  store one digest; whether a code is there is all that crosses, never the
  digits; and the sentence under the field when it will not read is
  modelpipe's own, with neither the paste nor the binding's type names in it.
  It is a decode and not a glance at the shape, so a ticket with a bad
  checksum is refused where it was typed — and, as the spec says, ASCII
  whitespace around a paste is trimmed and Unicode whitespace is not. The one
  thing the form decides for itself, whether anything has been typed yet, is
  decided over that same ASCII set, so the app holds no second opinion about
  which spaces count in a pairing string or a ticket, and a field holding one
  non-breaking space is read and refused rather than passed off as empty. The
  app keeps no parser of its own, in a debug build either.
  <!-- test: PairingReaderTests.testTheAcceptedVectorsReadAsTheSpecSays -->
  <!-- test: PairingReaderTests.testAQRScanReadsTheSameTicketAsThePaste -->
  <!-- test: PairingReaderTests.testABareTicketCarriesNoCode -->
  <!-- test: PairingReaderTests.testARefusalIsModelpipesOwnSentenceAndNotThePaste -->
  <!-- test: PairingReaderTests.testATicketWithABadChecksumIsRefusedAsItIsTyped -->
  <!-- test: PairingReaderTests.testUnicodeWhitespaceIsNotTrimmed -->
  <!-- test: PairingFieldTests.testOnlyModelpipesOwnWhitespaceCountsAsNothingTyped -->
  <!-- test: PairingReaderWiringTests.testTheFactoryHandsOutModelpipesReaderInDebugToo -->
  <!-- test: PairingReaderWiringTests.testTheAppModelTakesThatReaderByDefault -->
- Pairing is modelpipe's own, and the pipe a device paired over is the one
  it keeps: the whole `ticket-code` string goes to `PipeConnector.pair`,
  which dials the ticket, waits for the far machine, spends the code there,
  and hands back this device's key over a pipe still up. The key becomes
  the provider's token and that pipe becomes its first session, so nothing
  is dialled twice. A refused code leaves no provider behind and says where
  the next attempt starts, and the form stops asking for a token once it
  has a code to fetch one with.
  <!-- test: ModelpipeConnectorPairingTests.testThePipeTheCodeWasRedeemedOverIsTheSession -->
  <!-- test: ModelpipePairRefusalTests.testARefusedCodeKeepsItsOwnCaseAndSaysWhereToGetANewOne -->
  <!-- test: AppModelPairingTests.testARedeemedCodeBecomesTheProvidersTokenAndThePipeConnects -->
  <!-- test: AppModelPairingTests.testARefusedCodeAddsNoProviderAndSaysWhy -->
  <!-- test: ScreenGalleryUITests.testAPairingCodeIsRedeemedInsteadOfAskingForAToken -->
- A desktop still on gglib 0.18 pairs another way: its edge spends the code
  and its proxy has no such route, so it answers the pairing request `404`.
  Pairing with one says that the code has been spent, and that gglib there
  needs updating to a version newer than 0.18 before it is asked for another.
  Any other status, and any answer carrying no status at all, says only that
  the code may have been spent — an unexplained answer is not blamed on a
  version.
  <!-- test: ModelpipePairRefusalTests.testADesktopTooOldToPairSaysToUpdateItAndThatTheCodeIsSpent -->
  <!-- test: ModelpipePairRefusalTests.testAStatusOtherThanNotFoundIsNotBlamedOnTheDesktopsVersion -->
  <!-- test: ModelpipePairRefusalTests.testAnyOtherAnswerThatIsNotAPairingAnswerSaysTheCodeMayBeSpent -->
- A pairing is the longest wait in the app, so the app being left under one
  is ordinary rather than exotic: the pipe it was about to install is hung up
  instead of kept, the key is stored all the same, and the provider is left
  with a pill to press and a status the next resume will dial. While a pairing
  is out, Reconnect is not offered for that provider, because pressing it
  would dial the machine being replaced with the token being replaced.
  <!-- test: AppModelPairingTests.testAPairingThatLandsWhileTheAppIsAwayKeepsItsKeyAndItsPill -->
  <!-- test: AppModelPairingTests.testReconnectIsNotOfferedWhileAPairingIsOut -->
- The name typed for this device travels with the pairing as its label, and
  the other machine lists this device under it. A name that is blank once
  trimmed is not sent at all: no label, rather than an empty one. The app
  model never sends the provider's name, which names the other machine, in
  its place.
  <!-- test: ModelpipeConnectorPairingTests.testTheLabelRidesAsGivenAndABlankOneIsNotSent -->
  <!-- test: AppModelPairingTests.testTheNameTypedForThisDeviceIsWhatTheRedeemCarries -->
  <!-- test: AppModelPairingTests.testWithNoDeviceNameTheProvidersNameIsNotSentInItsPlace -->
- The modelpipe binding is linked and answers across the boundary: a string
  that is not a ticket comes back as an `MpError` with a sentence in it. The
  xcframework is a binary fetched at resolve time and checked against a uniffi
  checksum only on first use, so a mismatched pair traps on a device rather
  than failing a build — something has to call across the boundary on every
  run, and this is it. Its four statuses cross into the app's own unchanged.
  <!-- test: BindingTests.testTheBindingIsLinkedAndAnswersAcrossTheBoundary -->
  <!-- test: BindingTests.testEveryPipeStatusCrossesUnchanged -->
  <!-- test: BindingTests.testARelayedPipeCountsAsConnected -->
- A real connector has modelpipe read the ticket before it dials, with the
  same call the form reads what is typed with, so a ticket that is not one and
  an empty token each cost nothing — which matters for the bare ticket a
  device that already holds its key is added by, where every request through
  the pipe would be refused at the far edge after a dial spent finding out. A
  string that carries a code is refused there too: a code is redeemed once,
  through the pairing, and dialling it would spend it on nothing.
  <!-- test: ModelpipeConnectorTests.testATicketOfTheWrongShapeIsRefusedWithoutDialling -->
  <!-- test: ModelpipeConnectorTests.testAPairingStringWithACodeIsRefusedWithoutDialling -->
  <!-- test: ModelpipeConnectorTests.testAnEmptyTokenIsRefusedEvenThoughTheBindingWouldNotWantIt -->
- This device keeps one endpoint key per machine it pairs with, so the
  fingerprint the other machine recorded as this device paired still names
  this device after a relaunch, rather than a peer that stopped existing when
  the app was quit. This app gives the keys a directory of their own under
  Application Support, readable by this user alone and marked out of the
  backup, and modelpipe names and writes them inside it; two machines are two
  keys, because a relay allows one live connection per endpoint and a phone
  talking to two desktops needs two. The key admits nothing — what admits this
  device is the token beside it in the Keychain — and
  [ADR 0004](adr/0004-the-connect-identity-is-a-file.md) is why it is a
  file all the same. Naming each key file used to be this app's job and is
  now the binding's, so the two have to land on the same name or every
  already-paired device would quietly introduce itself as a stranger, with no
  build failure and no log line. A test asserts that name as a literal from
  both sides of the boundary.
  <!-- test: BindingTests.testTheKeyFilesNameIsTheSameRuleOnBothSidesOfTheBoundary -->
  <!-- test: PipeIdentityFilesTests.testTheKeysLiveInADirectoryWhoseNameDoesNotMove -->
  <!-- test: BindingTests.testADeviceThatKeepsItsKeyIsTheSameDeviceNextTime -->
  <!-- test: ModelpipeConnectorIdentityTests.testTheShippedConnectorKeepsAKeyWhereItSaysItDoes -->
  <!-- test: ModelpipeConnectorIdentityTests.testEveryDialCarriesTheDirectoryThisDeviceKeepsItsKeysIn -->
  <!-- test: ModelpipeConnectorPairingTests.testAPairingIsMadeAsTheDeviceThatWillDialLater -->
  <!-- test: PipeIdentityFilesTests.testNamingTheDirectoryPutsNothingInIt -->
  <!-- test: PipeIdentityFilesTests.testTheDirectoryIsMadePrivateAndKeptOutOfTheBackup -->
- A key that machine's modelpipe will not accept — one half written by a
  process that was killed, say — is thrown away and the dial tried once more,
  because the advice it used to be refused with, remove the file or choose
  another path, is not something a phone offers anybody. That happens inside
  the binding now, which is the layer that decides the file's name. Once
  only: a refusal that reaches this app is one the discard could not fix, so
  it is not dialled again here and the person gets the sentence instead.
  <!-- test: BindingTests.testAKeyThisDeviceCannotUseIsThrownAwayAndTheDialTriedAgain -->
  <!-- test: ModelpipeConnectorIdentityTests.testAnIdentityRefusalIsNotDialledAgainOnThisSide -->
  <!-- test: ModelpipeConnectorTests.testAnIdentityFileThatCannotBeUsedIsASentenceAndNotWorthDiallingAgain -->
- A failure from the transport, from a pairing, or from an identity file
  this device cannot use, reaches the person as a sentence, never as the
  binding's own debug rendering, and says whether trying again is worth it.
  <!-- test: ModelpipePairRefusalTests.testEveryPairingErrorArrivesAsASentenceAndNotADebugRendering -->
  <!-- test: ModelpipePairRefusalTests.testTheFailuresNoRetryCanFixAgreeWithTheBinding -->
  <!-- test: ModelpipeConnectorTests.testATransportErrorArrivesAsASentenceAndNotADebugRendering -->
  <!-- test: ModelpipeConnectorTests.testABadTicketIsNotWorthDiallingAgain -->
  <!-- test: ModelpipeConnectorTests.testTheBindingDecidesWhatIsWorthRepeating -->
  <!-- test: ModelpipeConnectorTests.testAnIdentityFileThatCannotBeUsedIsASentenceAndNotWorthDiallingAgain -->
- A pipe that dies on its own still says `closed`. The binding ends its status
  sequence on any close, and nothing above the seam writes a status when a
  stream merely finishes, so the session writes it before finishing.
  <!-- test: ModelpipeSessionTests.testAPipeThatDiesOnItsOwnStillSaysClosed -->
- `relayed` is held back for a moment in case a direct path is behind it, and
  shown when nothing better follows. A hole punch commonly reaches a relay
  first, and a pill that flashes "Relayed" reads as a warning about a
  connection that is still being made.
  <!-- test: ModelpipeSessionTests.testRelayedDoesNotFlashWhenDirectIsAMomentBehindIt -->
  <!-- test: ModelpipeSessionTests.testRelayedIsShownWhenNothingBetterFollows -->
- A pipe's base URL has to be loopback with a port, not merely something
  `URL(string:)` accepted — it parses strings with spaces and no scheme at all.
  <!-- test: ModelpipeSessionTests.testAnAddressOffLoopbackIsRefused -->
- A dial the person asked for says why it failed; one they did not — the
  resume dials every pipe it is holding none of — says nothing and leaves the
  pill as the way back. A machine that is asleep would otherwise raise an
  alert on every return to the foreground, carrying only the last provider's
  sentence.
  <!-- test: AppModelQuietDialTests.testADialSomebodyAskedForSaysWhatWentWrong -->
  <!-- test: AppModelQuietDialTests.testAResumeThatFindsTheMachineAsleepSaysNothing -->
- A dial whose task is called off complains to nobody: nobody is waiting
  for its answer.
  <!-- test: AppModelQuietDialTests.testADialThatIsCalledOffSaysNothing -->
- When the Keychain will not read a pipe's ticket or token for a dial, as
  before the device's first unlock, the dial says the Keychain's own
  reason, on the question waiting for the pipe or in the alert. Only a
  credential that is not there is called missing: a missing one is a reason
  to pair again, and a refused read is not.
  <!-- test: AppModelKeychainReadTests.testAReadTheKeychainRefusesIsSaidAsThatRefusal -->
  <!-- test: AppModelKeychainReadTests.testASendWaitingOnThePipeShowsTheRefusalOnItsQuestion -->
  <!-- test: AppModelKeychainReadTests.testAQuietDialLogsTheRefusalAndRaisesNoAlert -->
  <!-- test: AppModelPipeTests.testConnectWithoutSecretsRefusesWithASentence -->
  <!-- test: KeychainSecretsTests.testAReadThatFailsForAnyOtherReasonThrows -->
- A pipe that dies quietly is forgotten, so the next resume dials it again
  instead of finding a dead session installed and refusing.
  <!-- test: AppModelQuietDialTests.testASessionThatEndedIsForgottenSoAResumeCanDialAgain -->
  <!-- test: AppModelQuietDialTests.testAnOldSessionEndingDoesNotRemoveTheOneThatReplacedIt -->
- Pairing waits for the far machine before spending the code, and the real
  `mpPair` is what waits. A dial returns once the local port is bound, not
  once the peer answers, and a redeem sent into that gap is answered `502` by
  this device's own end of the pipe, which never had a backend to reach.
  That spends the one-time code on nothing and needs a fresh
  `gglib remote invite`.
  <!-- test: BindingTests.testPairingWaitsForTheFarMachineBeforeSpendingTheCode -->
- The mock pipe walks idle → relayed → direct, can be forced closed, and a
  late subscriber gets the current status first.
  <!-- test: MockPipeTests.testStatusWalksIdleRelayedDirectThenClosedOnDemand -->
- A pipe that goes away without being asked says which side to look at. The
  binding reports a shutdown and a failed listener and nothing else, so a peer
  that simply stopped answering closes with no reason recorded — and that
  silence, not an open pipe, is what it is read as.
  <!-- test: PipeCloseReasonTests.testEveryReasonThatWasNotAskedForHasASentenceNamingASide -->
  <!-- test: ModelpipeSessionTests.testAPeerThatSimplyVanishesIsSaidToHaveVanished -->
  <!-- test: AppModelCloseReasonTests.testAPeerThatVanishesLeavesAReasonBesideTheStatusAndOneSentence -->
- A close the app asked for — the background, a reconnect, a provider deleted
  — explains nothing and says nothing, because it is something the person just
  did.
  <!-- test: PipeCloseReasonTests.testAHangUpThisAppAskedForIsNotWorthASentence -->
  <!-- test: AppModelCloseReasonTests.testAHangUpTheAppPerformedExplainsNothingAndSaysNothing -->
- Each pipe keeps when its machine was last heard, through a relaunch, and
  Settings says it; once the machine has failed to answer, and never while a
  pipe reconnects, a line under the pill names it with that time. The line
  under a `tunnel_unavailable` refusal names the other machine as well as this
  device, and a refused pairing says to run `gglib remote forget` there first
  if this device is still listed.
  <!-- test: AppModelLastHeardTests.testAPipeThatConnectsIsHeardThen -->
  <!-- test: AppModelLastHeardTests.testAPipeThatGoesQuietKeepsItsTime -->
  <!-- test: AppModelLastHeardTests.testARefusalWrittenOnThisSideIsNotHearing -->
  <!-- test: AppModelLastHeardTests.testAFinishedReplyIsHeard -->
  <!-- test: AppModelLastHeardTests.testAModelListAndAStatusAnswerAreHeard -->
  <!-- test: AppModelLastHeardTests.testRemovingTheProviderForgetsWhenItWasHeard -->
  <!-- test: AppModelLastHeardTests.testTheLineSaysTheTimeAndTheDateWhenItWasNotToday -->
  <!-- test: LastHeardStoreTests.testTheTimeSurvivesARelaunchOfTheStore -->
  <!-- test: LastHeardStoreTests.testAStoreWrittenBeforeTheColumnOpensWithItEmpty -->
  <!-- test: SilenceCaptionTests.testTheCaptionStaysAwayWhileAPipeReconnects -->
  <!-- test: SilenceCaptionTests.testTheCaptionShowsWhenAConnectedPipeGoesQuietUntilItConnects -->
  <!-- test: SilenceCaptionTests.testTheCaptionShowsWhenThePipeClosesOrTheDialFails -->
  <!-- test: SilenceCaptionTests.testAServerAddedByAddressIsNeitherHeardNorMarked -->
  <!-- test: SilenceCaptionTests.testTheCaptionShowsWhenARequestFindsNoTunnel -->
  <!-- test: QuietMachineTests.testTheTunnelHintNamesTheOtherMachineAsWellAsThisDevice -->
  <!-- test: QuietMachineTests.testARefusedPairingSaysToForgetAStillListedDeviceFirst -->
  <!-- test: QuietMachineTests.testAQuietMockGoesBackToLookingAndDoesNotClose -->
- Settings shows what each live pipe says about itself: its path, the loopback
  port it bound, and what its endpoint spent on relays.
  <!-- test: ModelpipeSessionTests.testTheReadingsCrossTheSeamInTheAppsOwnVocabulary -->
- Settings says the day this build stops opening, read from the provisioning
  profile signed into it: a free team's build stops with its profile, seven
  days after the profile was issued, and a later build can carry the same
  one. A build with no profile, from the simulator, the App Store or
  TestFlight, has no such line.
  <!-- test: ProvisioningProfileTests.testTheDateIsReadFromTheListInsideTheEnvelope -->
  <!-- test: ProvisioningProfileTests.testABlobWithNoListHasNoDate -->
  <!-- test: ProvisioningProfileTests.testAListWithoutAnExpirationDateHasNoDate -->
  <!-- test: ProvisioningProfileTests.testABundleWithNoProfileHasNoDate -->
  <!-- test: ProvisioningProfileTests.testABundlesProfileIsReadUnderItsName -->
  <!-- test: SettingsBuildExpiryTests.testTheLineSaysTheDayThisBuildStopsOpeningWhereThePersonIs -->
  <!-- test: SettingsBuildExpiryTests.testABuildWithNoDateHasNoLine -->
  <!-- test: ScreenGalleryUITests.testTheProvidersListAndTheTicketCountInSettings -->
- Settings names the gglib and the llama.cpp this build carries, say "gglib
  0.28.0-rc.2 · llama.cpp b11669", as gglib's own framework reports them
  from `build_info()`, in every build, on the Mac and on iOS. The row is
  read from the framework the app links, never written down, and the
  package's tests make the same call through the Mac's framework and hold
  its answer to the `binding.json` vendored beside the Swift, so a binding
  and a framework from two releases fail there rather than at uniffi's
  check on a device.
  <!-- test: SettingsCarriedVersionsTests.testTheLineNamesGglibsVersionAndTheLlamaCppPin -->
  <!-- test: SettingsCarriedVersionsTests.testTheRowReadsTheLinkedFramework -->
  <!-- test: LinkedGGLibTests.testTheLinkedFrameworkIsTheOneTheVendoredBindingNames -->
  <!-- test: ScreenGalleryUITests.testTheProvidersListAndTheTicketCountInSettings -->
- The mock is DEBUG-only. A build without one refuses a perfectly good
  ticket with a sentence about the build, instead of mocking a pipe that
  is not there.
  <!-- test: UnavailablePipeTests.testABuildWithNoPipeRefusesAGoodTicketInsteadOfMockingOne -->
  <!-- test: UnavailablePipeTests.testTheRefusalIsASentenceThatBlamesTheBuildAndNotTheUser -->
- A provider can run on this iPhone's own engine, "This iPhone", one per
  device, behind a seam shaped as the pipe's is: the engine serves gglib at
  a loopback address with a key of its own, and the ordinary provider talks
  to that. The simulator launched without `-ggchat-mock-engine` and the Mac
  run no engine, offer nothing on-device and refuse a serve with a sentence
  about the build. A DEBUG build on iOS launched with it walks the mock
  engine, which adds the provider at launch, is idle once served, and walks
  loading → ready within the first chat that names its model. Opening a
  conversation on it serves the engine once; a send goes the chat route with
  gglib's progress asked for, is never a run, has no Draw switch, and raises
  the ring from the context the engine loaded its model with. A model too
  big for the device is refused with `model_does_not_fit`, and the line
  under the refusal says where to pick a smaller one. Removing the provider
  takes the engine down, a serve still starting included, and a serve asked
  for while the engine goes down waits until it is down. The kind is stored
  as `{"onDevice":{}}`, which a build from before it cannot read.
  <!-- test: ProviderConfigTests.testEachKindIsStoredAsItWasNamed -->
  <!-- test: ProviderConfigTests.testThisIPhonesEngineHasASession -->
  <!-- test: ProviderConfigTests.testThisIPhonesEngineIsNotAPairedMac -->
  <!-- test: SpeaksGGLibTests.testThisIPhonesEngineSpeaksGGLib -->
  <!-- test: SpeaksGGLibTests.testThisIPhonesEngineHasNoRuns -->
  <!-- test: SpeaksGGLibTests.testThisIPhonesEngineHasNoDrawSwitch -->
  <!-- test: UnavailableEngineTests.testABuildWithNoEngineOffersNoneAndRefusesToServe -->
  <!-- test: MockEngineTests.testTheStatusWalksFromIdleToReadyAndEndsStopped -->
  <!-- test: MockEngineTests.testTooBigIsRefusedAs507ModelDoesNotFitAndLoadsNothing -->
  <!-- test: AppModelEngineTests.testOpeningThisIPhoneServesItsEngineOnceAndListsItsModel -->
  <!-- test: AppModelEngineTests.testASendOnThisIPhoneAsksForProgressAndIsNeverARun -->
  <!-- test: AppModelEngineTests.testThisIPhoneOffersNoDraw -->
  <!-- test: AppModelEngineTests.testTheRingLandsFromTheEnginesUsage -->
  <!-- test: AppModelEngineTests.testATooBigModelIsRefusedWithAdviceForThisIPhone -->
  <!-- test: AppModelEngineTests.testWithNoEngineASendOnThisIPhoneIsRefusedWithASentence -->
  <!-- test: AppModelEngineTests.testThisIPhoneIsAddedOnce -->
  <!-- test: AppModelEngineTests.testRemovingThisIPhoneTakesItsEngineDown -->
  <!-- test: AppModelEngineTests.testRemovingThisIPhoneWhileItsEngineStartsLeavesNothingServing -->
  <!-- test: AppModelEngineTests.testAServeWhileTheEngineGoesDownWaitsUntilItIsDown -->
  <!-- test: OnDeviceUITests.testAReplyOnThisIPhoneRaisesTheRing -->
- A model browser finds a model to run on this iPhone: a search of
  Hugging Face at the top, then "On this iPhone", the models installed and
  the downloads on their way, then what gglib suggests for it, one line
  each, the model, its quantization and size, and a chip saying whether it
  fits, "Fits · 16K", "Short context · 4K", "Too big for this iPhone",
  "Can't tell yet" or "Can't tell". A search's results take the
  suggestions' place, each the model with its owner beside it and its
  size, context and downloads under them, leaving out what the repository
  does not say. Each leads to a page for its repository with a row per
  quantization: its size, its chip and a download button; a suggestion's
  chip sits beside its link, not in it, so each takes its own taps. Every
  chip in the browser's lists ends in an info glyph and is a button:
  pressed, it opens a sheet saying how gglib judged the model, in words
  from the figures it judged it by, and for a suggestion gglib's own
  sentence on why that one; VoiceOver hears the chip's words and that it
  shows how gglib judged it. Only a verdict gglib could not reach because
  the first bytes of the file ended before its header did says a download
  will settle it. The browser reads this iPhone's memory once each time it
  opens, says when under the suggestions and under a repository's
  quantizations, and asks every verdict on it with that one reading; the
  app computes no size and no verdict. A quantization too big for this
  iPhone has no download button. Choosing one adds This iPhone the first
  time and starts its download; a model already on this iPhone while there
  is no This iPhone, as after it was removed, offers Use, which adds This
  iPhone with that model chosen. The ways in are This iPhone in Add
  provider, beside Server and Pipe, which shows the browser in place of a
  form, with nothing to name, since a device has one such provider, and
  which first run names, on the conversation list and in the detail pane;
  Settings' "Models on this iPhone", which leads to it; and "Find a
  model…" under This iPhone in the model list, the composer's and the
  panel's, which opens the browser in a sheet of its own. Looking adds
  nothing. Add provider keeps what is typed in Server and Pipe as the kind
  changes, and holds the kind while a code is being redeemed. None of it
  is shown where the build runs no model, so the simulator without the
  mock and the Mac show Server and Pipe alone.
  <!-- test: AppModelLibraryTests.testTheReadingIsSampledOncePerOpen -->
  <!-- test: AppModelLibraryTests.testATooBigQuantizationCannotBeDownloaded -->
  <!-- test: AppModelLibraryTests.testChoosingModelsCreatesThisIPhoneOnce -->
  <!-- test: AppModelLibraryTests.testTheBrowserSaysWhenItReadTheDevice -->
  <!-- test: AppModelLibraryTests.testASearchGoesOnAPageAtATime -->
  <!-- test: AppModelLibraryTests.testWithNoEngineNothingIsBrowsedOrDownloaded -->
  <!-- test: AppModelLibraryTests.testTheChipSaysEachVerdictInAFewWords -->
  <!-- test: AppModelLibraryTests.testTheWhySheetSaysEachFigureOrThatItIsNotKnown -->
  <!-- test: AppModelLibraryTests.testOnlyACutOffHeaderPromisesThatADownloadWillTell -->
  <!-- test: ModelBrowserLayoutTests.testThisIPhoneIsAKindOnlyWhereModelsRunHere -->
  <!-- test: ModelBrowserLayoutTests.testAddProvidersBrowserOpensNoSheetOfItsOwn -->
  <!-- test: ModelBrowserLayoutTests.testAChipsSheetSaysWhatGglibSaidOfTheModel -->
  <!-- test: ModelBrowserLayoutTests.testEachRowSaysItsLineInFewWords -->
  <!-- test: ModelBrowserLayoutTests.testUseAddsThisIPhoneWithThatModelOnlyWhileThereIsNone -->
  <!-- test: OnDeviceUITests.testSettingsLeadsToTheModelBrowser -->
  <!-- test: ScreenGalleryUITests.testAnEmptyPhoneOffersThisIPhoneInAddProvider -->
  <!-- test: ScreenGalleryUITests.testABrowsedModelSaysWhetherItFits -->
- A model chosen in the browser downloads to this iPhone, into
  `ggchat-models` under Application Support, which is readable by this user
  alone and marked out of the backup at launch, before each download and
  again after each one finishes. A download larger than the room the volume
  has for it, or one with no such directory to go into, is refused under its
  row before the library hears of it. The row shows a bar, how much of how
  much has come, and Cancel, which takes the row away and stops the
  download; gglib keeps the bytes it fetched, and choosing it again carries
  on from them, while the mock deletes its partial file. Under "On this
  iPhone" the same download is one line, the model, its bar, how far it
  has come and a cross that calls it off; once done, its row on the
  repository's page is marked as on this iPhone.
  Going to the background pauses every download beside the replies, the row
  saying "Paused, resumes when ggchat is open", and coming back resumes them
  from the bytes they had; the library hears the pauses and resumes in the
  order the scenes came. A finished download joins This iPhone's model list
  at once, the list being what the library has installed, and an engine that
  is serving lists it again too. The browser's "On this iPhone" lists the
  models installed with their sizes and chips above the downloads on their
  way, and Settings says what the models on this iPhone take. An installed
  one is removed by a swipe, by Remove… in the menu a long press on its row
  opens, or by the section's Edit, and each asks first, naming the model
  and the room it frees. One no longer listed as installed is refused
  before anything is touched. The engine is put down before the files go
  while its status says a model is loading or ready, while a reply goes
  through it or waits for it, and while a shutdown is already under way,
  which a second removal joins; a reply through it is kept as Stop keeps
  it, and the engine serves again at the next request. One that may hold
  no model goes on serving. While the model is being removed, a send
  naming it is refused with a sentence. The model leaves This iPhone's
  list, and every chat on This iPhone that had it, and This iPhone's
  default if it was the model, are left with none, matched by name, after
  the listing, so the listing does not make the model left This iPhone's
  default; a chat left with no model and no default says "Choose a model"
  and does not send. Chats on other models and other providers keep
  theirs. A removal the library refuses says why under the section and
  leaves the files, the list, the chats and the default as they were,
  though the engine may have been put down by then. The simulator without
  the mock and the Mac show none of it.
  <!-- test: AppModelDownloadTests.testADownloadsBarOnlyGoesUpThroughAPauseAndAResume -->
  <!-- test: AppModelDownloadTests.testCancelTakesTheRowAndThePartialAway -->
  <!-- test: AppModelDownloadTests.testAFinishedDownloadJoinsThisIPhonesModels -->
  <!-- test: AppModelDownloadTests.testADownloadThereIsNoRoomForIsRefused -->
  <!-- test: ModelsDirectoryTests.testTheDirectoryIsPrivateAndOutOfTheBackup -->
  <!-- test: ModelsDirectoryTests.testTheLaunchMarksADirectoryMadeWithoutTheMark -->
  <!-- test: ModelsDirectoryTests.testAFinishedDownloadMarksTheDirectoryAgain -->
  <!-- test: ModelsDirectoryTests.testTheAppsOwnModelsAreUnderApplicationSupport -->
  <!-- test: ModelsDirectoryTests.testTheRoomIsTheVolumesFigureForAnImportantDownload -->
  <!-- test: AppModelScenePhaseTests.testTheDownloadsPauseBesideTheRepliesAndResumeInTurn -->
  <!-- test: MockLibraryDownloadTests.testAPauseHoldsAWalkAtItsBytesAndAResumeGoesOn -->
  <!-- test: MockLibraryDownloadTests.testAFinishedDownloadIsInstalledAndListedByTheEngineSharingItsCatalogue -->
  <!-- test: ModelBrowserLayoutTests.testOnThisIPhoneHoldsTheInstalledAndTheDownloadsOnTheirWay -->
  <!-- test: ScreenGalleryUITests.testADownloadFillsItsBarAndTheModelJoinsTheList -->
  <!-- test: AppModelRemovalTests.testARemovedModelLeavesTheChatsAndTheDefaultThatHadItWithNone -->
  <!-- test: AppModelRemovalTests.testARemovalLeavesTheOtherChatsAlone -->
  <!-- test: AppModelRemovalTests.testARemovalPutsALoadedEngineDown -->
  <!-- test: AppModelRemovalTests.testARemovalKeepsWhatAReplyThroughTheEngineHad -->
  <!-- test: AppModelRemovalTests.testARemovalLeavesAnIdleEngineServing -->
  <!-- test: AppModelRemovalTests.testARemovalOfAModelNoLongerListedTouchesNothing -->
  <!-- test: AppModelRemovalTests.testARemovalTheLibraryRefusesKeepsTheFilesTheChatsAndTheDefault -->
  <!-- test: AppModelRemovalRaceTests.testTheEngineIsDownBeforeTheFilesGo -->
  <!-- test: AppModelRemovalRaceTests.testASecondRemovalWaitsForTheEngineTheFirstPutsDown -->
  <!-- test: AppModelRemovalRaceTests.testASendNamingAModelBeingRemovedIsRefused -->
  <!-- test: ModelBrowserLayoutTests.testTheRemovalQuestionNamesTheModelAndTheRoomItFrees -->
  <!-- test: OnDeviceUITests.testAModelIsRemovedFromTheMenuOnItsRow -->
- On iOS the library behind the browser is gglib's own, through its
  framework: Hugging Face searched, each quantization judged against the
  reading the browser took, downloads followed a step at a time, and the
  models installed listed and removed, files, emptied folder and row. Its
  database, `gglib.db`, is kept in `ggchat-gglib` under Application Support,
  readable by this user alone and out of the backup like the models beside
  it, and it is opened at the first question, so a build that asks none
  makes neither folder. It asks Hugging Face with no token, so a repository
  that wants one says it needs a token. A download's steps stay in one
  stream through a pause and go on after the resume, end after done or
  failed, and ending the stream first calls gglib's download off. Each of
  gglib's records and errors becomes the app's own, case for case. No build
  shows the browser over it yet: outside a DEBUG build launched with
  `-ggchat-mock-engine`, which walks the mock library, the engine is
  unavailable, and with it every way in.
  <!-- test: MappingTests.testEachVerdictCrossesAsTheAppsOwn -->
  <!-- test: MappingTests.testEachGglibErrorIsTheAppsOwnCase -->
  <!-- test: GglibLibraryTests.testAFailedOpenIsNotKeptAndTheNextQuestionOpensAgain -->
  <!-- test: GglibLibraryTests.testPausingAndResumingOpenNothingButReachAnOpenLibrary -->
  <!-- test: GglibLibraryTests.testEveryQuestionThrowsGglibsRefusalAsTheAppSaysIt -->
  <!-- test: DownloadStepsTests.testAPauseKeepsTheStreamOpenAndTheResumeGoesOnInIt -->
  <!-- test: DownloadStepsTests.testAFailureIsSaidWithItsReasonAndEndsTheStream -->
  <!-- test: DownloadStepsTests.testCancellingTheConsumerCancelsTheWatch -->
  <!-- test: InstalledLibraryTests.testTheLibraryIsOpenedInPrivateFoldersOutOfTheBackup -->
  <!-- test: InstalledLibraryTests.testAFolderWhoseMarkWasClearedIsOutOfTheBackupAgainAtTheNextOpen -->
  <!-- test: InstalledLibraryTests.testAModelIsListedJudgedAndRemovedWithItsFiles -->
- This iPhone's engine runs in the foreground only
  ([ADR 0015](adr/0015-the-on-device-engine-is-foreground-only.md)).
  It is served when a conversation on it opens or a send needs it, and
  loads a model within the first request that names one. A send while it is
  not serving waits for it, as one through a pipe waits for the pipe, with
  "Waiting for This iPhone to start its engine", and a serve refused puts
  its sentence under the question. The status pill, a pipe's slot, says how
  the conversation's model is, with a memory chip: "Not loaded", "Loading
  40%", "Ready", "Load again" once it could not be loaded, which serves the
  engine afresh and asks the question again, or "Too big" once the engine
  refused it, which opens the model browser; VoiceOver hears "Model …".
  Going to the background puts the replies down first, keeping what arrived
  with Continue, and then the engine, inside the same grace; a serve that
  lands while the app is away takes itself down, and coming back starts
  nothing. A memory warning puts the engine down unless a reply is going
  through it; a send that was waiting on a serve it put down serves the
  engine again, and is answered.
  <!-- test: AppModelEngineLifecycleTests.testASendWaitsForTheEngineThroughItsLoadThenReplies -->
  <!-- test: AppModelEngineLifecycleTests.testTheBackgroundPutsTheEngineDownOnlyOnceTheReplyHasEnded -->
  <!-- test: AppModelEngineLifecycleTests.testAServeThatLandsWhileAwayTakesItselfDown -->
  <!-- test: AppModelEngineLifecycleTests.testComingBackStartsNothingAndTheNextSendServesAgain -->
  <!-- test: AppModelEngineLifecycleTests.testAMemoryWarningPutsTheEngineDownOnlyWithNoReplyGoingThroughIt -->
  <!-- test: AppModelEngineLifecycleTests.testASendJoiningAServeAMemoryWarningPutsDownServesAgain -->
  <!-- test: AppModelEngineLifecycleTests.testLoadAgainServesAfreshAndAsksTheQuestionAgain -->
  <!-- test: AppModelEngineLifecycleTests.testARefusedServePutsItsSentenceUnderTheWaitingQuestion -->
  <!-- test: SessionStatusTests.testThePillSaysEachStateInAFewWords -->
- On an iPhone, This iPhone runs gglib's own engine, in a release build and
  in a DEBUG one launched without `-ggchat-mock-engine`: gglib's proxy on a
  loopback port, with a key new for each serve, in front of llama.cpp
  running in the app's own process. Its library is `gglib.db` in
  `ggchat-gglib` and the weights in `ggchat-models`, both under Application
  Support, readable by this user alone and out of the backup. It is the
  model library's own: the engine is served from the one library the browser
  asks, opened at the first question or serve and kept, and opened again
  only after an open that failed, so the process holds one library over one
  `gglib.db`. The engine's states are the pill's, each under the name
  gglib's proxy lists the model by, so the pill finds the conversation's
  model and reads Ready once it has loaded; its errors are the app's, case
  for case. The engine's state is followed from where it stands until it
  says stopped, and following stops when nothing listens. A serve that came
  up anywhere but this device's loopback address is shut down and refused.
  The app model serves it, loads the model within the first send and puts it
  down in the background through gglib's engine as through the mock. A reply
  gglib's engine streamed through its proxy, recorded on the Mac, reads
  through the ordinary provider with its text, its prompt progress, its
  finish and the context the engine loaded the model with, which raises the
  ring. The simulator and the Mac run no engine. The iOS app asks for the
  increased memory limit, so a build signed for a phone needs a provisioning
  profile that carries it.
  <!-- test: MappingTests.testEachEngineStateIsSaidAsTheAppsOwn -->
  <!-- test: InstalledLibraryTests.testTheLibraryIsOpenedInPrivateFoldersOutOfTheBackup -->
  <!-- test: GglibEngineTests.testAServeGglibRefusesIsTheAppsErrorAndTheReadingCrossedAsRead -->
  <!-- test: GglibEngineTests.testTheSessionIsAtTheServersAddressWithItsKey -->
  <!-- test: GglibEngineTests.testAServerOffLoopbackIsShutDownAndRefused -->
  <!-- test: GglibEngineTests.testTheStreamWalksFromWhereTheEngineStandsAndFinishesAfterStopped -->
  <!-- test: GglibEngineTests.testAConsumerThatStopsListeningStopsThePulling -->
  <!-- test: GglibEngineTests.testShuttingDownTwiceIsShuttingDown -->
  <!-- test: GglibEngineTests.testTheEngineIsServedFromTheLibrarysOwnOpen -->
  <!-- test: GglibEngineTests.testTheEngineIsOfferedOnlyOnADevice -->
  <!-- test: GglibEngineChoiceTests.testTheMacRunsNoEngine -->
  <!-- test: AppModelGglibEngineTests.testAFirstSendServesGglibsEngineAndThePillReadsReady -->
  <!-- test: AppModelGglibEngineTests.testTheBackgroundPutsGglibsEngineDownAndTheNextSendServesAgain -->
  <!-- test: PhoneStreamContractTests.testAReplyFromGglibsEngineOnThisIPhoneFinishesAndRaisesTheRing -->
  <!-- test: LiveGglibEngineTests.testOneReplyStreamsFromGglibsEngineAndTheStatusWalksToReady -->
  <!-- test: OnDeviceLiveUITests.testAReplyOnThisIPhoneComesFromGglibsOwnEngine -->
  <!-- test: SessionStatusTests.testOnlyASessionThatCanRunHasAPill -->
  <!-- test: SessionStatusTests.testATooBigModelSaysSoAndThePillOpensTheBrowser -->
  <!-- test: OnDeviceUITests.testAFirstSendLoadsTheModelThenReplies -->
  <!-- test: OnDeviceUITests.testATooBigModelSaysSoInThePill -->
- A bearer token is sent on every request and never reaches a log line.
  <!-- test: OpenAICompatibleProviderTests.testNoCredentialEverReachesALogLine -->
- No line the app writes as it dials a pipe, loses one or pairs carries a
  ticket, a token or a pairing code.
  <!-- test: AppModelPipeLogTests.testNoPipeOrPairingLineCarriesATicketATokenOrACode -->
- `PairedPipe`, `Paired` and `OpenAICompatibleProvider` print the key they
  hold as `<redacted>`, and a `ReadPairing` prints its ticket as the
  ticket's digest, whether interpolated, reflected or dumped, so a log line
  that interpolates one of them whole carries neither.
  <!-- test: RedactedDescriptionTests.testAPairedPipePrintsItsDeviceAndNeverItsKey -->
  <!-- test: RedactedDescriptionTests.testAReadPairingPrintsItsDigestAndNeverItsTicket -->
  <!-- test: PairedDescriptionTests.testPairedPrintsItsDeviceAndNeverItsKey -->
  <!-- test: RedactedDescriptionTests.testAProviderPrintsItsAddressAndNeverItsKey -->
- gglib's proxy status endpoint decodes when it answers and is `nil` on 404.
  A loop-guard trip is read under the key gglib sends, and under the one an
  older hub sent.
  <!-- test: OpenAICompatibleProviderTests.testProxyStatusIsNilOn404AndDecodesOn200 -->
  <!-- test: ProxyStatusHelperTests.testTheLoopGuardIsReadUnderTheKeyGGLibSendsAndTheOldOne -->
- A pipe with no session is not asked for its status pane, so the probe as a
  conversation opens raises no alert and keeps no answer. The pane is asked
  for again each time a pipe a conversation has been opened on comes up, and a
  probe called off before it was answered keeps nothing.
  <!-- test: AppModelProxyStatusTests.testProbingAPipeWithNoSessionRaisesNothingAndCachesNothing -->
  <!-- test: AppModelProxyStatusTests.testTheStatusPaneIsAskedForAgainWhenThePipeConnects -->
  <!-- test: AppModelProxyStatusTests.testAProbeCalledOffBeforeItsAnswerKeepsNothing -->
  <!-- test: AppModelProxyStatusTests.testAnAnswerThatArrivesAfterThePipeReconnectedIsNotKept -->
  <!-- test: AppModelOpeningTests.testThePaneIsAskedAboutWhenAFollowedPipeComesUp -->
  A probe that fails, the server out of reach or answering with an error,
  keeps nothing either, so the next one asks. A 404 is kept: that server is
  not asked again.
  <!-- test: AppModelProxyStatusTests.testAProbeThatFailsKeepsNothingAndTheNextOneAsks -->
  <!-- test: AppModelProxyStatusTests.testA404IsKeptAndNotAskedAgain -->
- Opening a conversation hands its provider to the model, which dials it if
  it is down, lists its models once the pipe is up, and asks about its status
  pane; a server added by address is asked at once. The work is the model's
  own, so a view task that SwiftUI calls off as it starts does not call it
  off. A pipe that was not answering yet when the conversation opened lists
  its models when it comes up, and one whose last try failed asks again the
  next time it comes up. A list asked for as a pipe comes up raises no alert
  when it fails, the first after an opening included, and a list the pipe
  already has is asked for again each time it comes back, one that fails then
  keeping the list it had. A second opening while the first runs
  asks nothing more, opening again once it has finished asks again for what
  it still lacks, and a list asked for by a task that was called off raises
  no alert.
  <!-- test: AppModelOpeningTests.testAServerAddedByAddressListsItsModelsAndIsAskedAboutItsPane -->
  <!-- test: AppModelOpeningTests.testOpeningAgainAfterAnOpeningFinishedAsksAgain -->
  <!-- test: AppModelOpeningTests.testAPipeNotAnsweringYetWhenTheConversationOpensListsItsModelsOnceItIs -->
  <!-- test: AppModelOpeningTests.testAPipeTheCodeWasRedeemedOverListsItsModelsOnceItIsUp -->
  <!-- test: AppModelOpeningTests.testAFollowedPipeThatComesBackAsksAgainForAListThatFailed -->
  <!-- test: AppModelOpeningTests.testOpeningIsNotCalledOffWithTheTaskThatAskedForIt -->
  <!-- test: AppModelOpeningTests.testASecondOpeningWhileTheFirstRunsAsksNothingMore -->
  <!-- test: AppModelOpeningTests.testARefreshWhoseTaskWasCalledOffRaisesNoAlert -->
- An unterminated code fence, as seen mid-stream, renders as a code block.
  <!-- test: MarkdownTests.testUnterminatedFenceIsStillACodeBlock -->
- A markdown table is drawn as a table and not as its source: its header,
  the alignment of each column and its rows, every row a cell per column,
  and each cell keeping its inline styling. VoiceOver reads it a row at a
  time, each cell after its column's name. Text that only looks like a table
  stays a paragraph, with none of its lines dropped.
  <!-- test: MarkdownTableTests.testATableParsesIntoItsHeaderAlignmentsAndRows -->
  <!-- test: MarkdownTableTests.testACellKeepsItsInlineMarkdown -->
  <!-- test: MarkdownTableTests.testEveryRowHasACellPerColumn -->
  <!-- test: MarkdownTableTests.testACaretCellIsKeptAsWritten -->
  <!-- test: MarkdownTableTests.testATableUnderAParagraphLineTakesOnlyItsOwnLines -->
  <!-- test: MarkdownTableTests.testTableTextThatIsNotATableIsKeptAsAParagraph -->
  <!-- test: MarkdownBlockViewTests.testATableBlockIsDrawnAsATableAndNotAsCode -->
  <!-- test: MarkdownBlockViewTests.testACodeBlockIsStillDrawnAsCode -->
  <!-- test: MarkdownBlockViewTests.testVoiceOverReadsATableARowAtATime -->
- Math in a reply reads exactly as the model wrote it, `$…$`, `$$…$$`,
  `\(…\)` and `\[…\]` alike: markdown takes none of its backslashes as
  escapes and none of its `*` as emphasis, and a `|` in it splits no table
  cell. A `$` is math only by pandoc's rules, so `$5 and $6` stays money,
  and `\$` is a dollar sign. Math over several lines reads as one line.
  <!-- test: MathSpanTests.testBackslashesInMathAreKept -->
  <!-- test: MathSpanTests.testAsterisksInMathAreNotEmphasis -->
  <!-- test: MathSpanTests.testMoneyIsNotMath -->
  <!-- test: MathSpanTests.testAFailedCloseGivesUpOnlyThatDollar -->
  <!-- test: MathSpanTests.testMathKeepsTheStyleAroundIt -->
  <!-- test: MathSpanTests.testMathInEveryKindOfBlock -->
  <!-- test: MathSpanTests.testABarInMathDoesNotSplitATableCell -->
  <!-- test: MathSpanTests.testMathOverLinesReadsAsOneLine -->
  <!-- test: MathSpanTests.testALineThatWouldEndTheParagraphLeavesTheMathAlone -->
  <!-- test: MathSpanTests.testCodeIsLeftAlone -->
  <!-- test: MathSpanTests.testEmphasisOutsideMathStillApplies -->
- A reply being streamed, to a conversation here or to a Mac's chat, is
  parsed again only after the blocks no later token can change, so the
  parsing a token costs stays the size of the last block or two however long
  the reply grows. Every step gives the blocks a parse of the whole text
  would, a code fence or a table still open at the end included. Text that
  may hold a link reference definition, a carriage return or a byte-order
  mark, each of which reaches across blocks, is parsed whole.
  <!-- test: LiveMarkdownTests.testEveryPrefixOfASampleReplyParsesAsTheWholeDoes -->
  <!-- test: LiveMarkdownTests.testEveryPrefixOfRandomMarkdownParsesAsTheWholeDoes -->
  <!-- test: LiveMarkdownTests.testACodeFenceStillOpenAtTheEndStaysOpen -->
  <!-- test: LiveMarkdownTests.testATableStillOpenAtTheEndStaysOpen -->
  <!-- test: LiveMarkdownTests.testADefinitionAfterAParagraphStillMakesItALink -->
  <!-- test: LiveMarkdownTests.testTextThatDoesNotCarryOnIsParsedAfresh -->
  <!-- test: LiveMarkdownTests.testABlockOverlappingTheOneBeforeItIsNoBoundary -->
  <!-- test: LiveMarkdownTests.testOnlyALabelAtTheStartOfALineMayBeADefinition -->
  <!-- test: LiveMarkdownTests.testSettledBlocksAreNotParsedAgain -->
  <!-- test: LiveReplyMarkdownTests.testTheChatRowParsesOnlyWhatATokenCanChange -->
  <!-- test: LiveReplyMarkdownTests.testAMacChatRowParsesOnlyWhatADeltaCanChange -->
- A `ProviderConfig` holds no credential; a pipe config carries only a
  digest of its ticket.
  <!-- test: ProviderConfigTests.testPipeProviderRoundTripsAndHoldsOnlyADigest -->
- A pasted address becomes a base URL: a bare host gets `/v1`, a trailing
  slash is dropped, anything that is not http or https is refused.
  <!-- test: BaseURLNormalizationTests.testBareHostGetsV1AndTrailingSlashIsDropped -->
- Conversations, their messages in order, and providers survive a round
  trip through SwiftData; deleting a conversation cascades to its messages.
  <!-- test: SwiftDataStoreTests.testConversationsRoundTripWithMessagesInOrder -->
- Saving or deleting one provider or conversation fetches that row by its
  key.
  <!-- test: SwiftDataStoreTests.testOneProviderAmongManyIsUpdatedAndDeletedByItsOwnKey -->
  <!-- test: SwiftDataStoreTests.testOneConversationAmongManyIsUpdatedAndDeletedByItsOwnKey -->
- Saving a conversation sets only what changed: a field is set only when
  it differs, and a failure is encoded only when it is not the one already
  kept, so a save of an unchanged conversation marks no row.
  <!-- test: SwiftDataStoreWriteTests.testWritingAnUnchangedConversationChangesNoRow -->
  <!-- test: SwiftDataStoreWriteTests.testChangingOneThingChangesOnlyItsRow -->
  <!-- test: SwiftDataStoreWriteTests.testAFailureIsWrittenOnlyWhenItChanged -->
- Conversations, their messages and providers are kept in `ggchat-store` under
  Application Support, a directory readable by this user alone and marked out of
  the backup, and a store an earlier build left where SwiftData put it moves in
  with every conversation, the main file last, never replacing a file already
  there. When the store cannot be kept there, the app runs from memory with a
  notice saying so, and does not open the old place.
  <!-- test: StoreDirectoryTests.testTheStoreOpensInsideADirectoryNoBackupCarries -->
  <!-- test: StoreDirectoryTests.testADirectoryMadeWithoutTheMarkIsMarkedWhenTheStoreOpens -->
  <!-- test: StoreDirectoryTests.testTheStoresDirectoryAndFileNamesDoNotMove -->
  <!-- test: StoreDirectoryTests.testTheAppsOwnStoreIsInsideTheDirectoryUnderApplicationSupport -->
  <!-- test: StoreDirectoryTests.testSwiftDataNamesTheOldPlaceWithoutCreatingIt -->
  <!-- test: StoreMoveTests.testAStoreFromAnEarlierBuildMovesInWithEveryConversation -->
  <!-- test: StoreMoveTests.testAStoreLeftAsItsMainFileAloneMovesInWithEveryConversation -->
  <!-- test: StoreMoveTests.testAMoveCutShortFinishesOnTheNextLaunch -->
  <!-- test: StoreMoveTests.testAMoveStopsRatherThanReplaceAFileAlreadyInTheDirectory -->
  <!-- test: StoreMoveTests.testAStoreAlreadyInTheDirectoryIsNeverReplacedByAnOlderOne -->
  <!-- test: StoreDirectoryTests.testWithNowhereToKeepTheStoreNothingIsKeptAndTheNoticeSaysSo -->
  <!-- test: StoreFallbackTests.testADirectoryThatCannotBeMarkedIsNotUsed -->
  <!-- test: StoreFallbackTests.testAStoreThatWillNotOpenKeepsItsBytesAndNothingIsKept -->
  <!-- test: StoreFallbackTests.testAStoreThatWillNotOpenBesideAnOlderOneReportsBoth -->
  <!-- test: StoreFallbackTests.testWithNoApplicationSupportNothingIsKeptAndTheNoticeSaysSo -->
  <!-- test: StoreFallbackTests.testAFileAtTheOldPlaceThatCannotBeMarkedIsLoggedWithoutAPath -->
  <!-- test: StoreDirectoryTests.testANormalOpenHasNothingToSay -->
  <!-- test: StoreNoticeTests.testTheRedLineComesFirstAndEachLineReadsAsWritten -->
  <!-- test: StoreNoticeTests.testClosingHidesTheOlderStoresLineAndNeverTheRedOne -->
  <!-- test: StoreResetTests.testTheResetClearsTheStoreFromBothPlaces -->
- A chat holding a turn whose role this build does not know, one a newer
  build wrote, is left out of the list whole rather than read with that turn
  as a question or loaded without it, and the window says how many were left
  out and that they have not been deleted.
  <!-- test: StoreUnknownRoleTests.testAChatHoldingATurnThisBuildCannotReadIsLeftOutAndKept -->
  <!-- test: StoreUnknownRoleTests.testTheWindowSaysHowManyChatsWereLeftOut -->
- Sending streams the reply, with reasoning kept separately, into the
  conversation; a dropped stream keeps the partial reply on screen and
  Continue extends that same message rather than starting a new one.
  <!-- test: AppModelStreamingTests.testSendStreamsAReplyIntoTheConversation -->
  <!-- test: AppModelStreamingTests.testADroppedStreamKeepsThePartialAndContinueCarriesOn -->
- A reply to gglib is a run the hub owns, under an id minted on the phone, so
  locking the phone mid-reply loses none of it. Going to the background, or a
  connection dropping, stops reading and keeps what arrived with the run's id
  and the number of the last event read; coming back, a launch or the pipe
  coming up reads on after that number, nothing twice and nothing skipped,
  whichever byte the stream was cut at. A reading that got nothing is tried
  again after a pause, three times at most, and a start whose answer was lost
  is sent again under the same id. While the hub is still writing it, the
  reply says so and offers Stop, never Continue or Retry; Stop frees the
  conversation whether or not the hub can be reached. It ends as the run did;
  one the hub no longer has, or refuses to send, keeps its partial with
  Continue and a sentence saying why. A page that is not an event stream, as a
  captive portal answers with, is a drop to read on after, not a refusal.
  Stop, a deletion or removing the provider cancels a run. A hub without runs
  is sent the chat request as before, asked once, with nothing shown. Nothing
  but the run's id leaves the phone, and no log line carries it, the reply or
  an address.
  <!-- test: RunProviderTests.testAPutStartsARunAndAHubWithoutTheRouteIsUnsupported -->
  <!-- test: RunProviderTests.testEventsAreFramesNumberedFromOneThenTheRunsReport -->
  <!-- test: RunProviderTests.testAStreamCutAtEveryByteReadsOnFromItsCursorToTheSameReply -->
  <!-- test: RunProviderTests.testAnEventAtOrBelowTheCursorIsNotAppliedAgain -->
  <!-- test: RunProviderTests.testNotFoundARefusalAndADropAreToldApart -->
  <!-- test: RunProviderTests.testAReportThatCannotBeReadIsARefusal -->
  <!-- test: RunProviderTests.testCancelPostsToTheRunAndReadsItsReport -->
  <!-- test: RunProviderTests.testARunsIDNeverReachesALogLine -->
  <!-- test: RunStoreTests.testARunsIDAndCursorAreKeptWithItsMessage -->
  <!-- test: RunStoreTests.testAStoreOpensAcrossTheChangeInBothDirections -->
  <!-- test: AppModelRunTests.testASendToGGLibIsARunAndAnythingElseGoesTheOldWay -->
  <!-- test: AppModelRunTests.testAHubWithoutRunsIsAskedOnceAndTheReplyGoesTheOldWay -->
  <!-- test: AppModelRunTests.testARefusedRunIsAFailureOnTheQuestion -->
  <!-- test: AppModelRunTests.testStopCancelsTheRunAndTheBackgroundDoesNot -->
  <!-- test: AppModelRunTests.testAReplyStillBeingWrittenOffersNeitherContinueNorRetry -->
  <!-- test: AppModelRunTests.testDeletingAConversationCancelsTheRunStillWritingItsReply -->
  <!-- test: AppModelRunCatchUpTests.testTheBackgroundKeepsTheRunAndComingBackReadsOnFromItsCursor -->
  <!-- test: AppModelRunCatchUpTests.testABackgroundWhileReadingOnKeepsTheRunAgain -->
  <!-- test: AppModelRunCatchUpTests.testAReplyReadOnEndsAsTheRunDid -->
  <!-- test: AppModelRunCatchUpTests.testAnEmptyReplyTheHubNoLongerHasLeavesTheQuestionWithRetry -->
  <!-- test: AppModelRunCatchUpTests.testADropInFrontReadsOnInsteadOfFailing -->
  <!-- test: AppModelRunCatchUpTests.testALaunchReadsOnAReplyTheLastOneWalkedAwayFrom -->
  <!-- test: AppModelRunCatchUpTests.testEveryCutOfTheReplyReadsOnToTheSameText -->
  <!-- test: AppModelRunWayOutTests.testARefusalOfTheEventsGivesTheRunUpWithASentence -->
  <!-- test: AppModelRunWayOutTests.testAnUnreachableHubIsWaitedForAndStopAlwaysGetsOut -->
  <!-- test: AppModelRunWayOutTests.testRemovingTheProviderGivesUpItsRuns -->
  <!-- test: AppModelRunReadOnTests.testADropBeforeTheFirstEventIsReadOnAfterAPause -->
  <!-- test: AppModelRunReadOnTests.testAHubThatNeverAnswersIsNotAskedAgainAndAgain -->
  <!-- test: AppModelRunReadOnTests.testAPutWhoseAnswerWasLostIsSentAgainUnderItsID -->
  <!-- test: AppModelRunReadOnTests.testAReturnReadsOnAtAnAddressWithNoPipe -->
  <!-- test: AppModelRunReadOnTests.testNoLogLineNamesARunItsTextOrAnAddress -->
- The conversation list says, beside a title, "Writing" while a reply is still
  being written, in front or by the hub, and "New" when one finished, failed
  or was given up while its chat was not on screen with the app in front,
  until that chat is shown. Selecting is not reading: a launch keeps every
  mark, the one it restores included. A reply that ends with its chat on
  screen is never new, nor is one the person stopped; going Back to the list
  is leaving it. Showing one moves nothing in the list. The mark is kept with
  the conversation in its store, and a store opens across that change both
  ways; nothing about it leaves the phone.
  <!-- test: AppModelListMarkTests.testAReplyStillBeingWrittenIsWritingInTheList -->
  <!-- test: AppModelListMarkTests.testAReplyThatEndsWhileAnotherIsOpenIsUnreadUntilOpened -->
  <!-- test: AppModelListMarkTests.testAReplyThatEndsWhileItsChatIsOnScreenIsNeverUnread -->
  <!-- test: AppModelListMarkLaunchTests.testALaunchKeepsEveryMarkUntilItsChatIsShownInFront -->
  <!-- test: AppModelListMarkLaunchTests.testAReplyReadOnAtLaunchInTheRestoredConversationIsUnread -->
  <!-- test: AppModelListMarkLaunchTests.testAReplyThatEndsWithNoChatShownIsUnread -->
  <!-- test: AppModelListMarkLaunchTests.testAChatOpenedAfterGoingBackIsReadWhateverFollowsItsAppear -->
  <!-- test: AppModelListMarkLaunchTests.testAReplyThePersonStoppedIsNeverUnread -->
  <!-- test: AppModelListMarkTests.testTheMarksLeaveTheOrderAsItWas -->
  <!-- test: AppModelListMarkTests.testEachMarkHasAWordAndALabel -->
  <!-- test: UnreadStoreTests.testTheUnreadMarkIsKeptWithItsConversation -->
  <!-- test: UnreadStoreTests.testAStoreOpensAcrossTheUnreadChangeInBothDirections -->
- On a regular-width window taller than it is wide and at least 600 points
  across, an iPhone Duo open and held upright or an iPad in portrait, the
  conversation list is kept beside the chat rather than behind the sidebar
  button. Folded, a Duo is a phone and its list a screen back; a window
  wider than it is tall, or too narrow for the list and a 320-point chat,
  shows or hides the list as the system does. Wherever the list is beside
  the chat, the chat narrows to make room rather than the list lying over
  it. The sidebar button still hides the list, until the next unfolding or
  turn upright puts it back. On a phone, where iOS lays a split view's list
  over the chat whatever it is asked, the app lays the two side by side
  itself, the list at three eighths of the width as Claude's own app keeps
  it and never under 240 points, with the sidebar button at the chat's
  leading edge. Wherever the list is a column beside the chat, its header
  holds its title and the new-conversation button, and Providers and
  Settings sit in a bar at its foot. The window is read by its width and
  the tallest height seen at it, so the keyboard, which only takes height
  away, never changes the layout under the field being typed in.
  <!-- test: SidebarPinningTests.testAnOpenDuoHeldUprightKeepsTheListBesideTheChat -->
  <!-- test: SidebarPinningTests.testAWideWindowLeavesTheListToTheSystem -->
  <!-- test: SidebarPinningTests.testAFoldedDuoIsAPhoneWithItsListAScreenBack -->
  <!-- test: SidebarPinningTests.testAFoldedDuoOnItsSideLeavesTheListToTheSystem -->
  <!-- test: SidebarPinningTests.testASquareWindowLeavesTheListToTheSystem -->
  <!-- test: SidebarPinningTests.testAWindowTooNarrowForTheListAndAChatLeavesTheListToTheSystem -->
  <!-- test: SidebarPinningTests.testAPhoneGivesTheListThreeEighthsOfTheWidthAsClaudesAppDoes -->
  <!-- test: SidebarPinningTests.testTheListIsNeverNarrowerThan240Points -->
  <!-- test: SidebarPinningTests.testTheKeyboardTakingHeightLeavesAnOpenDuoReadAsTall -->
  <!-- test: SidebarPinningTests.testTurningOrFoldingIsReadAfresh -->
  <!-- test: SidebarPinningTests.testTheFirstReadingIsTakenAsItIs -->
- An iPhone Duo open on its side and half open is a book. The chat is on
  the trailing page, the size of the outside screen and drawn as it is
  there, and the conversation list is on the leading page, the two meeting
  at the fold with nothing drawn across it. In that pose the chat's top bar
  is the list button, its title and a panel button: the panel, "This chat",
  takes the list's place on the leading page with the chat's model, picked
  from the composer's list of every provider's models with the system's
  search in place of the chips, and its provider, Thinking, its tools in a
  section of their own (the master switch, then a switch for each server the
  Mac offers, which cannot be turned while it is off), system prompt,
  context counts and server
  status, the ones the chat offers, with the servers listed once, not
  again under the status, and the top bar leaves those out. A
  Mac's chat has its model, Thinking, context and server there, its tools
  and prompt being the Mac's. Laid flat, the chat has the whole screen and
  the list button lays the list beside it at half the width; half opened
  again, the list comes back, and a hide holds until then. A window less
  than 600 points high, a folded Duo or a large iPhone on its side, is not
  read as an open Duo. The chat is laid out once whatever is beside it, so
  turning, half opening, laying flat and hiding the list keep its draft.
  <!-- test: BookPagesTests.testAnOpenDuoOnItsSideIsReadAsSideways -->
  <!-- test: BookPagesTests.testAFoldedDuoOnItsSideAndAProMaxTurnedAreNot -->
  <!-- test: BookPagesTests.testAnOpenDuoUprightIsNot -->
  <!-- test: BookPagesTests.testTheWalkWaivesTheHeightButNotTheRoomForTwoPages -->
  <!-- test: BookPagesTests.testHalfOpenThePagesMeetAtTheFold -->
  <!-- test: BookPagesTests.testFlatThereAreNoPages -->
  <!-- test: BookPagesTests.testAPropFoldAcrossTheScreenMakesNoPages -->
  <!-- test: BookPagesTests.testAFoldLeavingAPageTooNarrowMakesNoPages -->
  <!-- test: BookPagesTests.testAListShownByHandWhileFlatGetsHalfTheScreen -->
  <!-- test: BookPagesTests.testAChatKeptHereShowsEverythingItIsOffered -->
  <!-- test: BookPagesTests.testAChatOfferedNothingStillShowsItsModelAndPrompt -->
  <!-- test: BookPagesTests.testAMacsChatHasNoToolsOrPromptHere -->
  <!-- test: ToolsMenuTests.testThePanelRowTitlesAreTheMacsServers -->
  <!-- test: BookPagesUITests.testTheChatIsOnTheTrailingPageAndItsPanelOnTheLeading -->
- Each paired Mac has a section of its own in the list, "On home", with the
  chats gglib keeps there, listed at launch, when its pipe comes up and on a
  pull, each with the time it last changed (the date too when not today),
  and marked "Writing" while the Mac is writing a reply to one. The
  phone's own chats are then headed "On this phone", with a line under them
  saying they are kept only on this phone and the Mac does not keep them.
  Opening one reads its questions and replies live, and Back drops them:
  no conversation and no message row comes from the Mac into the store
  (ADR 0007). A Mac that reads its chats only to a device through its tunnel
  says so, a server added by address has no section, and the launch's quiet
  dial raises no alert. While the Mac cannot be reached, or its last list
  failed, its section shows the titles its list last showed with "last seen
  22:13", kept on the provider's row through a relaunch and gone with it, and
  opening one says the Mac is unreachable; a failed list keeps them as they
  were. A pull lists again, and the background stops it dialling. A gglib too
  old to share its chats has no section until a list works, and a Mac this
  device has lost its ticket for says to pair again. A chat on screen keeps
  its rows while it is read again. The wire shapes replay the bodies gglib records, and a row
  whose metadata cannot be read still opens without it.
  <!-- test: HubChatsWireTests.testTheListReadsEveryChatInTheHubsOrder -->
  <!-- test: HubChatsWireTests.testAnOpenedChatReadsItsConversationAndRows -->
  <!-- test: HubChatsWireTests.testNullAndMissingOptionalsDecodeAsNil -->
  <!-- test: HubChatsWireTests.testUnknownKeysArePassedOver -->
  <!-- test: HubChatsWireTests.testMetadataThatCannotBeReadIsDroppedAndTheRowKept -->
  <!-- test: HubChatsProviderTests.testTheListIsReadFromChatsWithTheKey -->
  <!-- test: HubChatsProviderTests.testAChatIsOpenedByItsIDWithTheKey -->
  <!-- test: HubChatsProviderTests.testDeviceNotNamedIsAHubThatDoesNotShareItsChats -->
  <!-- test: HubChatsProviderTests.testAnother403IsARefusal -->
  <!-- test: HubChatsProviderTests.testA404IsNotFound -->
  <!-- test: HubChatsProviderTests.testAPageThatIsNotJSONA5xxAndNoAnswerAreDrops -->
  <!-- test: HubChatsProviderTests.testJSONThatCannotBeReadIsARefusal -->
  <!-- test: HubChatsListTests.testTheMacsChatsAreListedWhenItsPipeComesUp -->
  <!-- test: HubChatsListTests.testOnlyAPairedMacHasASection -->
  <!-- test: HubChatsListTests.testOpeningAChatReadsItsRowsAndKeepsNothing -->
  <!-- test: HubChatsListTests.testTheTwoKindsOfSelectionDropEachOther -->
  <!-- test: HubChatsListTests.testAMacThatDoesNotShareItsChatsSaysSo -->
  <!-- test: HubChatsListTests.testALaunchListsEachPairedMacsChats -->
  <!-- test: HubChatsListTests.testAQuietDialWithNothingToDialWithRaisesNoAlert -->
  <!-- test: HubChatsListTests.testAPullDialsAPipeThatIsDownAndListsAgain -->
  <!-- test: HubChatsSeenTests.testAnUnreachableMacShowsTheTitlesItLastSawAndWhen -->
  <!-- test: HubChatsSeenTests.testOpeningOneWhileTheMacIsUnreachableSaysSo -->
  <!-- test: HubChatsSeenTests.testAChatOpenedDuringADialThatFailsSaysTheMacIsUnreachable -->
  <!-- test: HubChatsSeenTests.testTheTitlesAreKeptAfterEveryListAndSurviveARelaunch -->
  <!-- test: HubChatsSeenTests.testRemovingTheProviderForgetsItsTitles -->
  <!-- test: HubChatsSeenTests.testAStoreOpensAcrossTheTitlesChangeInBothDirections -->
  <!-- test: HubChatsSeenTests.testAChatSaysTheTimeItChangedAndTheDateWhenNotToday -->
  <!-- test: HubChatsSeenTests.testAChatWhoseTimeCannotBeReadShowsNone -->
  <!-- test: HubChatsWireTests.testAChatsTimeReadsAsUTC -->
  <!-- test: HubChatsWireTests.testATimeInAnotherShapeReadsAsNothing -->
  <!-- test: HubChatsOutcomeTests.testAFailedListKeepsWhatWasSeenAndSaysWhen -->
  <!-- test: HubChatsOutcomeTests.testAPullListsAgainThroughAPipeThatIsUp -->
  <!-- test: HubChatsOutcomeTests.testAnOlderGglibHasNoSectionUntilItLists -->
  <!-- test: HubChatsOutcomeTests.testAMacWithNothingToDialWithSaysToPairAgain -->
  <!-- test: HubChatsOutcomeTests.testTheBackgroundStopsARefreshFromDialling -->
  <!-- test: HubChatsOutcomeTests.testAChatOnScreenKeepsItsRowsWhileItIsReadAgain -->
- A paired Mac's chat is carried on from this phone. A send puts the new text
  as `{conversation_id, content}` and nothing else, with the ids of its images
  when it has some and its Thinking choice when that changes (both below), and the Mac runs the reply as an agent run and saves both rows; its text, reasoning and a line for
  each tool it calls are read from the run into memory, and once the run ends
  the rows the Mac saved are read in its place. Nothing of it is written to the
  store (ADR 0007). Stop cancels the run, and nothing reads on beside it until
  the Mac answers. A chat with no model, while nothing is running on the Mac,
  says to start a model there, a chat the Mac is already writing to says so,
  here too while this phone holds that reply, and a gglib that takes the turn
  as a chat run is one without turns;
  a refused send, or one to a Mac out of reach, puts its text back. A turn
  whose answer was lost is kept, still Writing, and put again under its id,
  whose answer settles it; a list that names its run marks it started, and one
  that does not leaves it Writing, since the Mac names a run only once it has
  reserved it, and the phone sends it again when the Mac next answers: that
  list, coming back or the pipe coming up, with its chat open or not, but not
  once Stop ended it or a refusal took it. A send refused while its chat is
  not on screen gives its text back, with why, when the chat is next opened.
  Leaving the chat does not stop a send on its way: one the leaving cut short
  is sent again at once, and the phone reads its reply quietly until it ends;
  leaving a chat whose reply is being read, and the background, walk away and
  cancel nothing; opening it again, coming back and the pipe coming up read on
  from the last event, none applied twice, paced as this phone's own replies
  are. Only the run's id and
  its chat are kept, on the provider's row: a launch reads the run from its
  start, and a run the Mac no longer has, a list that no longer names it, or
  removing the provider forgets it. The chat says "Writing" in the list while
  this phone holds its reply.
  <!-- test: HubChatsWireTests.testATurnIsTheRecordedBodyWithOnlyItsTwoKeys -->
  <!-- test: HubTurnProviderTests.testATurnIsPutAsAnAgentRunWithOnlyItsTwoKeys -->
  <!-- test: HubTurnProviderTests.testNoModelAndAReplyInProgressAreTheirOwnRefusals -->
  <!-- test: HubTurnProviderTests.testEveryOtherAnswerMeansWhatItShould -->
  <!-- test: HubTurnProviderTests.testAnAgentRunsEventsAreItsTextReasoningAndToolLines -->
  <!-- test: HubTurnProviderTests.testAnErrorIsPassedOnAndAnEventThatCannotBeReadIsPassedOver -->
  <!-- test: HubTurnProviderTests.testCancellingATurnCancelsItsRun -->
  <!-- test: HubChatContinueTests.testASendPutsOnlyTheNewTextAndTheReplyIsReadThenReplacedByTheMacsRows -->
  <!-- test: HubChatContinueTests.testStopCancelsTheRunAndTheRowsAreReadOnceItEnds -->
  <!-- test: HubChatContinueTests.testEachRefusalIsSaidInTheViewAndKeepsNothing -->
  <!-- test: HubChatContinueTests.testASecondSendWhileTheMacWritesIsRefusedHere -->
  <!-- test: HubChatContinueTests.testAFailedRunSaysSoAndTheRowsAreReadAgain -->
  <!-- test: HubChatContinueTests.testAMacThatStartsAChatRunForATurnIsOneWithoutTurns -->
  <!-- test: HubChatLostTurnTests.testALostTurnIsKeptAndPutAgainUnderItsIDThenReadFromItsStart -->
  <!-- test: HubChatLostTurnTests.testALostTurnTheListDoesNotNameIsKept -->
  <!-- test: HubChatLostTurnTests.testADroppedTurnIsPutAgainWhenAListDoesNotNameIt -->
  <!-- test: HubChatLostTurnTests.testADroppedTurnInAChatNotOnScreenIsPutAgainOnComingBack -->
  <!-- test: HubChatLostTurnTests.testAStartedReplyIsNotPutAgain -->
  <!-- test: HubChatPutAgainTests.testARefusedSendIsNotPutAgainByAListOnItsWay -->
  <!-- test: HubChatPutAgainTests.testASendBeingPutIsNotPutBesideItself -->
  <!-- test: HubChatPutAgainTests.testADroppedSendIsNotPutWhileItsMacIsOutOfReach -->
  <!-- test: HubChatPutAgainTests.testAStoppedSendIsNotPutWhenThePipeComesBack -->
  <!-- test: HubChatPutAgainTests.testNothingIsPutOnTheWayToTheBackground -->
  <!-- test: HubChatPutAgainTests.testADroppedSendIsPutAgainWhenThePipeComesUp -->
  <!-- test: HubChatPutAgainTests.testARefusedSendOffScreenGivesItsTextBackOnOpening -->
  <!-- test: HubChatPutAgainTests.testASendCutShortByLeavingItsChatIsSentAgainAndReadToItsEnd -->
  <!-- test: HubChatLostTurnTests.testALostTurnPutAgainAfterItsRunEndedIsReadThenItsRows -->
  <!-- test: HubChatContinueTests.testASendToAMacOutOfReachGivesTheTextBack -->
  <!-- test: HubChatContinueTests.testAnAcceptedSendClearsTheTextGivenBack -->
  <!-- test: HubChatLostTurnTests.testALostTurnTheListNamesIsKeptAsStarted -->
  <!-- test: HubChatLostTurnTests.testNothingReadsOnBesideAStopWhoseCancelIsNotAnsweredYet -->
  <!-- test: HubChatReadOnTests.testLeavingTheChatWalksAwayAndOpeningItAgainReadsOnFromTheCursor -->
  <!-- test: HubChatReadOnTests.testTheBackgroundWalksAwayAndComingBackReadsOn -->
  <!-- test: HubChatReadOnTests.testAReadingThatGetsNothingReadsOnAfterEachPauseThenWaits -->
  <!-- test: HubChatReadOnTests.testARunTheMacNoLongerHasReadsTheRowsAndIsForgotten -->
  <!-- test: HubChatReadOnTests.testRemovingTheProviderForgetsItsRepliesAndCancelsNothing -->
  <!-- test: HubChatReadOnTests.testAMacChatSaysWritingWhileThePhoneHoldsItsReply -->
  <!-- test: HubChatHeldRunsTests.testALaunchReadsTheRunItKeptFromItsStartWhenItsChatOpens -->
  <!-- test: HubChatHeldRunsTests.testAListThatNoLongerNamesTheRunForgetsIt -->
  <!-- test: HubChatHeldRunsTests.testAStoreOpensAcrossTheHeldRunsChangeInBothDirections -->
- A turn to a Mac's chat can carry images, picked, pasted or dropped through
  the same downscale as this phone's own, with text or alone. Each is sent to
  the Mac first, its bytes the whole body of `POST /v1/attachments`, and the
  turn names them by the ids the Mac answers, as `images` beside
  `conversation_id` and `content`; a turn without images is the two keys it
  always was. The Mac's images are read by id from `GET /v1/attachments/{id}`
  as their rows are drawn, with nothing cached and on a session with no cache,
  held in memory only and dropped when the chat is left: no image of a Mac's
  chat, its own or one this phone sent, is written by this app to the store,
  a file or a URL cache (ADR 0007). Bytes whose hash is not their id are not kept, a row
  of images alone is drawn, and an image this phone sent is not read back
  while this phone still holds it; once the chat is left and opened again it
  is read like any other. A turn the Mac refuses because it no longer holds
  an image the turn or the chat names started nothing: a turn with images
  sends them again from the bytes held here and is put again under the same
  id, once, and one refused again, or a turn of text alone, says the Mac no
  longer has an image this chat carries. A turn put again after a lost answer carries its
  images without sending them again. A refused or unsent turn gives back its
  text and its images. A chat whose model this phone knows cannot read images
  refuses them here with gglib's sentence, and any other is sent them, for the
  Mac to refuse by name. A Mac whose gglib is from before images, with no
  upload route or refusing the key, says its gglib needs updating.
  <!-- test: HubChatsWireTests.testATurnWithImagesIsTheRecordedBodyWithItsImageIDs -->
  <!-- test: HubChatsWireTests.testAnUploadIsAnsweredWithTheImagesReference -->
  <!-- test: HubImagesProviderTests.testAnImageIsUploadedAsItsBytesAndNamedAsTheHubAnswers -->
  <!-- test: HubImagesProviderTests.testAnUploadToAGglibWithoutImagesTakesNoImagesAndTheRestAreRefusals -->
  <!-- test: HubImagesProviderTests.testAnImageIsFetchedAsItsBytes -->
  <!-- test: HubImagesProviderTests.testAFetchTheHubCannotAnswerIsNotFoundOrADrop -->
  <!-- test: HubImagesProviderTests.testAFetchedImageIsNeverKeptInAURLCache -->
  <!-- test: HubTurnProviderTests.testAnImageTheHubDoesNotHoldAndAGglibWithoutImagesAreTheirOwnRefusals -->
  <!-- test: HubChatImageSendTests.testEachImageIsSentThenTheTurnNamesThem -->
  <!-- test: HubChatImageSendTests.testATurnOfImagesAloneIsSentAndAnEmptyOneIsNot -->
  <!-- test: HubChatImageSendTests.testAnImageTheMacLetGoIsSentAgainAndTheTurnPutUnderTheSameID -->
  <!-- test: HubChatImageSendTests.testAMacThatKeepsNoImageIsSentThemOnceMoreAndThenSaysSo -->
  <!-- test: HubChatImageSendTests.testATextTurnRefusedForAnImageIsNotSentImagesAndSaysSo -->
  <!-- test: HubChatImageSendTests.testALostTurnIsPutAgainWithItsImagesWithoutSendingThemAgain -->
  <!-- test: HubChatImageSendTests.testARefusedTurnGivesBackItsTextAndImages -->
  <!-- test: HubChatImageSendTests.testASendToAMacOutOfReachGivesBackItsImages -->
  <!-- test: HubChatImageSendTests.testAMacWithoutImagesSaysItsGglibNeedsUpdating -->
  <!-- test: HubChatImageSendTests.testAChatWhoseModelCannotSeeRefusesImagesHere -->
  <!-- test: HubChatImageRowsTests.testARowOfImagesAloneIsDrawnWithItsImages -->
  <!-- test: HubChatImageRowsTests.testTheMacsImagesAreReadIntoMemoryOnceAndGoWithTheChat -->
  <!-- test: HubChatImageRowsTests.testOnlyTheBytesTheIdNamesAreKept -->
  <!-- test: HubChatImageRowsTests.testAnImageThisPhoneSentIsNotReadBack -->
- An image a tool makes on a paired Mac, while the Mac writes a reply this
  phone is reading, arrives on the run's `tool_call_complete` as gglib's
  `result.images`: each one's id, type and size, in the order the tool made
  them. They are drawn under the reply's text, with words or before any, in
  the order the tools made them, read from the Mac by id like the chat's
  other images and held in memory only (ADR 0007). A finished tool with no
  images, or with images that cannot be read, means nothing here, as before.
  Once the run ends, the tool's row the Mac saved carries the same images, and
  they are drawn as they were while the reply was written: on the next
  assistant row that has words, under its text and after its own images, in
  the order the tools made them across tool rows, without the words the model
  read, and as a reply of those images alone when no words come before the
  next question or the chat's end. A tool's row without images is still the
  Mac's to show. A saved reply's images are drawn under its text, a
  question's above its words. An image read while the reply was written is
  not read again for its row.
  <!-- test: HubTurnProviderTests.testAFinishedToolsImagesAreReadAndOneWithoutMeansNothing -->
  <!-- test: HubTurnProviderTests.testAnAgentRunsEventsAreItsTextReasoningAndToolLines -->
  <!-- test: HubChatToolImagesTests.testAToolsImagesJoinTheReplyInOrderAcrossToolCalls -->
  <!-- test: HubChatToolImagesTests.testTheImagesAToolMadeAreDrawnAsTheMacs -->
  <!-- test: HubChatImageRowsTests.testAToolsImagesGoUnderTheTextOfTheReplyThatFollows -->
  <!-- test: HubChatImageRowsTests.testAReplyThatEndedAfterItsToolIsItsImagesAlone -->
  <!-- test: HubChatToolImagesTests.testASavedReplysImagesAreDrawnUnderItsTextAndAQuestionsAbove -->
  <!-- test: HubChatImageRowsTests.testAToolsImagesAreReadFromTheMacByIdOnceFromReplyToRow -->
  <!-- test: RunsWireTests.testARecordedToolReplyReadsAsItsToolLineItsImageAndItsText -->
  <!-- test: HubChatsWireTests.testARecordedToolRowCarriesTheImageItsToolMade -->
- A conversation can carry a system prompt. It goes ahead of every request
  the conversation makes, Continue and Retry included, and an edit reaches the
  next one. It is never a row in the transcript and never stored as a
  message, so the messages a conversation keeps are the ones it shows. A
  blank prompt sends nothing, and the prompt survives a relaunch.
  <!-- test: ConversationTests.testASystemPromptGoesAheadOfTheMessagesAndIsNotOneOfThem -->
  <!-- test: AppModelSystemPromptTests.testTheSystemPromptIsSentAheadOfEveryRequestButNeverKept -->
  <!-- test: AppModelSystemPromptTests.testContinueAndRetryResendTheSystemPrompt -->
  <!-- test: SwiftDataStoreTests.testASystemPromptSurvivesTheRoundTrip -->
  <!-- test: WireTests.testASystemMessageIsSentWithTheSystemRole -->
- After a reply, a ring at the end of the model's row shows how much of the
  model's context the conversation uses, and pressing it gives the counts,
  what was trimmed and whether the reply was cut off; from 70% it shows the
  figure and from 90% a mark.
  <!-- test: ContextReadingTests.testThePercentRoundsAHalfUpAndNeverPassesAHundred -->
  <!-- test: ContextReadingTests.testSeverityTurnsAtSeventyAndNinetyAndEachHasAWord -->
  <!-- test: ContextReadingTests.testTheFigureShowsFromSeventyAndTheMarkFromNinety -->
  <!-- test: ContextReadingTests.testTheSheetSaysTheCountsTheTrimAndACutOffReply -->
  <!-- test: ContextReadingTests.testNumbersUseTheLocalesDigits -->
  <!-- test: ContextReadingTests.testVoiceOverHearsThePercentAndTheSeverityWord -->
  <!-- test: AppModelContextTests.testAFinishedReplyKeepsItsReadingOnBothRoutes -->
  <!-- test: AppModelContextTests.testAStoppedOrFailedReplyLeavesTheReadingAndAFinishedOneWithoutASizeClearsIt -->
  <!-- test: AppModelContextTests.testAnotherModelHidesTheReadingAndTheSameModelShowsItAgain -->
  <!-- test: AppModelContextTests.testReadingOnFromARunKeepsItsReading -->
  <!-- test: AppModelContextTests.testAReplyCutOffSaysSo -->
  <!-- test: ContextStoreTests.testTheReadingIsKeptAndAnUnchangedOneMarksNoRow -->
  <!-- test: ContextStoreTests.testAStoreOpensAcrossTheReadingInBothDirections -->
  <!-- test: ContextRingUITests.testAReplyRaisesTheRingAndItsSheetSaysTheCounts -->
- The numbers are gglib's and nothing is estimated, so there is no ring when
  gglib reports no context size, and a Mac chat's reading is held in memory
  only.
  <!-- test: ContextContractTests.testEveryWorkedReadingIsDrawnAsTheContractSays -->
  <!-- test: ContextContractTests.testEveryWorkedSourceNamesTheReplyThatDecides -->
  <!-- test: ContextReadingTests.testAReadingNeedsBothCountsAndASize -->
  <!-- test: WireTests.testUsageReadsGglibsTwoKeysAndReadsWithoutThem -->
  <!-- test: WireTests.testAContextKeyThatDoesNotReadCostsOnlyItself -->
  <!-- test: RunProviderTests.testARunsUsageFrameIsPassedOnWithItsFinishReason -->
  <!-- test: MockProviderTests.testTheMockReportsWhatItReadAndItsContext -->
  <!-- test: ContextReadingTests.testTheNewestFinishedRowDecidesAChatsReading -->
  <!-- test: HubChatsWireTests.testARowsMetadataReadsItsCountsSizeAndTrim -->
  <!-- test: HubTurnProviderTests.testATurnUsageEventIsThatCallsCounts -->
  <!-- test: HubChatContextTests.testAnOpenedChatShowsItsLastRepliesReading -->
  <!-- test: HubChatContextTests.testALiveCallReplacesItAndOneWithNoSizeHidesIt -->
  <!-- test: HubChatContextTests.testAChatTheMacStopsSendingDrawsNoRing -->
  <!-- test: HubChatContextTests.testNoReadingIsWrittenToThePhone -->
- A conversation whose model gglib lists as one that thinks has a Thinking
  switch in its top bar, kept with the conversation: off sends
  `reasoning_budget_tokens: 0` with every request from the next one on, to
  gglib alone, and on sends the request it always sent (ADR 0009).
  <!-- test: ThinkingWireTests.testAModelThatThinksSaysSoInItsCapabilities -->
  <!-- test: ThinkingWireTests.testOffIsABudgetOfZeroAndOtherwiseTheBodyIsByteForByteWhatItWas -->
  <!-- test: MockProviderTests.testABudgetOfZeroSkipsTheMocksReasoning -->
  <!-- test: AppModelThinkingTests.testOffIsSentOnSendContinueRetryAndARunsPut -->
  <!-- test: AppModelThinkingTests.testOnSendsNoKeyAndAServerThatIsNotGglibNeverSeesIt -->
  <!-- test: AppModelThinkingTests.testAModelTheListNamesAsNotThinkingIsNotSentTheBudget -->
  <!-- test: AppModelThinkingTests.testTheChoiceSurvivesARelaunch -->
  <!-- test: AppModelThinkingTests.testPickingAModelThatDoesNotThinkClearsTheChoice -->
  <!-- test: AppModelThinkingTests.testTheSwitchIsOfferedOnlyForAGglibModelListedAsThinking -->
  <!-- test: AppModelThinkingTests.testTheSwitchShowsOnUnlessOffAndAPressSetsWhatItShows -->
  <!-- test: AppModelThinkingTests.testTheSwitchSaysItsStateWithASymbolAndAWord -->
  <!-- test: ThinkingStoreTests.testTheChoiceIsKeptAndAnUnchangedOneMarksNoRow -->
  <!-- test: ThinkingStoreTests.testAStoreOpensAcrossTheChoiceInBothDirections -->
  <!-- test: ThinkingSwitchUITests.testTurningThinkingOffDropsTheReasoningRow -->
- A Mac's chat has the same switch and the Mac remembers it: the chat opens
  showing what the Mac remembers, the one turn that changes it says `off` or
  `default`, and this phone stores nothing of it, looking the chat's model up
  in that Mac's model list, which it reads when a chat is opened while it
  holds no list for that Mac, and again when the pipe comes up.
  <!-- test: HubChatsWireTests.testAnOpenedChatReadsTheThinkingItRemembersAndItsModel -->
  <!-- test: HubChatsWireTests.testATurnThatChangesThinkingIsTheRecordedBody -->
  <!-- test: HubTurnProviderTests.testATurnThatSaysTheThinkingChoiceIsPutWithIt -->
  <!-- test: HubChatThinkingTests.testAnOpenedChatShowsWhatTheMacRemembers -->
  <!-- test: HubChatThinkingTests.testAChangeGoesWithTheNextTurnOnceAndBackOnSaysDefault -->
  <!-- test: HubChatThinkingTests.testATurnTheMacTookIsWhatItRemembersAndASwitchSetMeanwhileIsSaidNext -->
  <!-- test: HubChatThinkingTests.testAChoiceChangedAtTheMacAfterThisPhoneSetItIsShown -->
  <!-- test: HubChatThinkingTests.testAMacChatsSwitchShowsOnUnlessOffAndAPressSetsWhatItShows -->
  <!-- test: HubChatThinkingTests.testATurnPutAgainCarriesTheSameChoice -->
  <!-- test: HubChatThinkingTests.testARefusedTurnKeepsTheChoice -->
  <!-- test: HubChatThinkingTests.testTheChoiceIsNeverStoredAndGoesWithTheChat -->
  <!-- test: HubChatModelListTests.testTheSwitchIsHiddenWhenTheModelIsNotInTheMacsList -->
  <!-- test: HubChatModelListTests.testAReplyThatNamesNoModelDoesNotHideTheOneBeforeIt -->
  <!-- test: HubChatModelListTests.testOpeningAChatListsTheMacsModels -->
  <!-- test: HubChatModelListTests.testAListThatFailsOnOpeningAChatRaisesNoAlert -->
  <!-- test: HubChatModelListTests.testAPipeComingUpListsAgainAndAFailedListKeepsTheOld -->
- A request refused before anything arrived has no reply to sit under, so
  the sentence that says why, the line about where to look and a Retry
  button go under the question instead. That covers a key the serving
  machine has stopped admitting, a request it refuses outright, such as one
  too long for the model's context, and a server that has gone away since
  its models were listed. Retry asks the same question again and adds
  no second copy of it. The sentence is kept with the message that ended the
  turn, the question or the partial reply, so it is still there after a
  relaunch. A question left with no reply by a stop, or by going to the
  background from a reply that is not a run, is not a failure: it keeps a
  Retry and no sentence.
  <!-- test: AppModelRefusalTests.testARefusalBeforeTheFirstTokenIsKeptOnTheQuestion -->
  <!-- test: AppModelRefusalTests.testRetryAsksAgainAndClearsTheRefusal -->
  <!-- test: AppModelRefusalTests.testAStopBeforeTheFirstTokenWritesNoFailureEvenIfAnErrorRaced -->
  <!-- test: AppModelRefusalTests.testABackgroundBeforeTheFirstTokenWritesNoFailure -->
  <!-- test: AppModelRefusalTests.testAQuestionLeftWithNoReplyCanBeAskedAgain -->
- A send, Retry or Continue through a pipe that is not connected waits for it
  (ADR 0006) under "Waiting for home · last heard 08:12", until the pipe
  connects, its dial is refused, or Stop, the background, a removed provider
  or a deleted conversation ends the wait. Removing a provider puts down the
  replies through it first, keeping what had arrived. Sends in several
  conversations can wait on one pipe, which is dialled once for all of them.
  <!-- test: PipeWaitTests.testASendDuringADialWaitsForItThenStreamsWithNoAlert -->
  <!-- test: PipeWaitTests.testASendOnAClosedPipeDialsIt -->
  <!-- test: PipeWaitTests.testARefusedDialPutsItsSentenceOnTheQuestion -->
  <!-- test: PipeWaitTests.testContinueWaitsForAPipeThatWentQuiet -->
  <!-- test: PipeWaitEndingTests.testStopWhileWaitingLeavesRetryAndNoFailure -->
  <!-- test: PipeWaitEndingTests.testABackgroundWhileWaitingLeavesRetryAndNoFailure -->
  <!-- test: PipeWaitEndingTests.testRemovingTheProviderEndsTheWait -->
  <!-- test: PipeWaitDeletionTests.testDeletingAConversationEndsItsWait -->
  <!-- test: ProviderRemovalTests.testRemovingAProviderCancelsTheReplyThroughItAndKeepsThePartial -->
  <!-- test: ProviderRemovalTests.testRemovingAProviderLeavesAReplyThroughAnotherAlone -->
  <!-- test: ConcurrentPipeWaitTests.testTwoSendsWaitingOnOnePipeDialItOnceAndBothStream -->
  <!-- test: ConcurrentPipeWaitTests.testTwoSendsWaitingOnAClosedPipeHangItUpOnce -->
  <!-- test: ConcurrentPipeWaitTests.testARefusedDialSaysWhyUnderBothQuestions -->
- A message can be sent in one conversation while another is still replying
  (ADR 0012). Each conversation has at most one reply in flight; Stop, the
  background and a removed provider put down the replies they cover and no
  others, and coming back reads on from every reply a hub went on writing.
  <!-- test: ConcurrentReplyTests.testTwoConversationsStreamAtOnceAndEachKeepsItsOwnReply -->
  <!-- test: ConcurrentReplyTests.testRemovingAProviderStopsOnlyTheRepliesThroughIt -->
  <!-- test: ConcurrentReplyTests.testTheBackgroundPutsDownEveryReply -->
  <!-- test: ConcurrentRunReadOnTests.testTwoDetachedRunsAreBothReadOnAfterAReturn -->
  <!-- test: AppModelRefusalTests.testRetryWhileAnotherConversationStreamsAsksAgain -->
- An error written into a stream that had already begun ends the reply
  there. gglib writes it as a bare `error` event and then `[DONE]`, and the
  `[DONE]` no longer counts the reply as finished. Text that had arrived stays
  as a partial reply with the error under it and Continue. When a stream ends
  with an error and the only text is gglib's own `⚠️ [proxy]` notice of it,
  the notice is dropped, because the app draws the error itself.
  <!-- test: OpenAICompatibleProviderTests.testAnErrorEventInsideAStreamEndsItWithTheErrorAndNoFinished -->
  <!-- test: AppModelStreamErrorTests.testAnErrorAfterSomeTextLeavesAPartialWithItsCode -->
  <!-- test: AppModelStreamErrorTests.testTheProxysNoticeIsNotKeptAsTheReply -->
  <!-- test: SwiftDataStoreTests.testAFailureSurvivesTheRoundTrip -->
  <!-- test: RefusalUITests.testARefusalIsDrawnUnderTheQuestionAndSurvivesARelaunch -->
- A chunk of a reply that the app cannot read is skipped and logged by its
  size alone, unless it has a top-level `error` member, which ends the reply
  as an error; an empty `data:` event is a keepalive and is ignored. A reply
  that skipped a chunk and got no text or reasoning fails with the first
  skipped chunk's decoding error instead of finishing empty.
  <!-- test: OpenAICompatibleProviderTests.testAnUnreadableChunkWithNoErrorMemberIsSkippedAndTheTextAfterItArrives -->
  <!-- test: OpenAICompatibleProviderTests.testAnEmptyDataLineIsAKeepaliveNotAFailure -->
  <!-- test: OpenAICompatibleProviderTests.testASkippedChunksBytesNeverReachALogLine -->
  <!-- test: OpenAICompatibleProviderTests.testAnUnreadableChunkThatCarriesAnErrorStillEndsTheReply -->
  <!-- test: OpenAICompatibleProviderTests.testAReplyThatSkippedAChunkAndGotNoTextOrReasoningFails -->
- A reply gives up only after ten minutes of silence, and while gglib reads a
  long prompt the reply shows "Reading 8,200 of 11,000 tokens" until its first
  word. Only gglib is asked for that progress, over a pipe or from a server
  that answered the status probe at its current address, and none of it is
  kept.
  <!-- test: PromptProgressTests.testAProviderTheRegistryBuildsStreamsOnASessionThatWaitsTenMinutes -->
  <!-- test: PromptProgressTests.testAChatStreamsOnTheStreamingSessionAndNothingElseDoes -->
  <!-- test: PromptProgressTests.testTheRequestAsksForProgressWhenToldAndHasNoSuchKeyOtherwise -->
  <!-- test: PromptProgressTests.testTheFixturesProgressFramesDecodeAsGGLibSentThem -->
  <!-- test: PromptProgressTests.testTheProviderPassesProgressOnBeforeTheFirstReasoningAndStillFinishesOnce -->
  <!-- test: PromptProgressTests.testAProgressMemberThatDoesNotReadIsDroppedAndTheRestOfTheChunkIsRead -->
  <!-- test: AppModelPromptProgressTests.testOnlyAPipeOrAServerThatAnsweredTheStatusProbeIsAskedForProgress -->
  <!-- test: AppModelPromptProgressTests.testAServerMovedAwayFromGGLibIsNotAskedForProgress -->
  <!-- test: AppModelPromptProgressTests.testTheLiveReplyHoldsTheLatestProgressAndNothingOfItIsKept -->
  <!-- test: AppModelPromptProgressTests.testTheReadingLineCountsInTheLocalesDigitsUntilSomethingElseArrives -->
- Exactly three custom glass surfaces exist, all in one file inside one
  `GlassEffectContainer`; `scripts/check_glass_sites.sh` counts them, and
  `scripts/check_no_hand_drawn_glass.sh` refuses any material or
  translucent fill elsewhere but one line, the material behind the
  scanner's caption over the camera, so Reduce Transparency and Increase
  Contrast are the system's to honour — and the test measures the glass
  going flat rather than trusting the setting, because the launch arguments
  that look like it are accepted and change nothing. Symbol effects and the
  streaming animation switch off under Reduce Motion, and the pills stack at
  accessibility type sizes.
  <!-- test: ReduceTransparencyUITests.testGlassGoesFlatWhenTransparencyIsReduced -->
- With `GGCHAT_LIVE_BASE_URL` set, the app model adds that server by URL,
  lists its models, streams a complete reply and probes the status endpoint.
  <!-- test: LiveAppModelTests.testAddByURLListModelsStreamAndProbeStatus -->
- Connecting a pipe provider walks the status to direct, fires the one
  haptic once, records the ticket's digest, and streams through the
  session's loopback URL with the token as the key; a forced close shows
  Closed, reconnecting dials again without counting the ticket twice, and
  neither a reconnect nor a delete leaves a Closed pill.
  <!-- test: AppModelPipeTests.testConnectWalksToDirectAndStreamsThroughTheSessionURL -->
  <!-- test: AppModelPipeTests.testForceClosedShowsClosedAndReconnectDialsAgain -->
  <!-- test: AppModelPipeTests.testAReconnectOrADeleteLeavesNoClosedPill -->
- A dial that lands after its provider was hung up or deleted closes itself
  instead of installing a pipe nothing on screen can reach any more, two
  dials in flight at once leave one connection rather than two, and a
  provider that has left the list is not dialled at all.
  <!-- test: AppModelDialTests.testADialThatLandsAfterADisconnectHangsUpInsteadOfInstallingItself -->
  <!-- test: AppModelDialTests.testRemovingAProviderMidDialLeavesNoConnectionBehind -->
  <!-- test: AppModelDialTests.testTwoOverlappingDialsLeaveExactlyOneConnection -->
  <!-- test: AppModelDialTests.testAProviderThatIsNoLongerOnTheListIsNotDialled -->
- A dial that is refused leaves a closed pill to press rather than no pill at
  all, a background leaves that pill where it was, and the next resume dials
  it again — one machine that was asleep is not a provider you have to
  relaunch the app to reach. A dial refused after it was called off says
  nothing instead.
  <!-- test: AppModelFailedDialTests.testAFailedDialLeavesAPillToPressAndAResumeThatDialsAgain -->
  <!-- test: AppModelFailedDialTests.testABackgroundAfterARefusedDialKeepsThePillToPress -->
  <!-- test: AppModelFailedDialTests.testARefusalThatArrivesAfterItsDialWasCalledOffSaysNothing -->
- Going to the background hangs up every pipe and writes the reply that was
  in flight into the conversation as a partial rather than losing it (a reply
  to gglib goes on being written there, and is read on); coming
  back dials again, every pipe at once, and only the pipes the app already
  had, so a machine that is asleep does not keep another waiting. The two
  take turns: a hang-up calls off a resume that is still dialling, a resume
  waits for a hang-up that is still closing, and a dial that lands while the
  app is away hangs itself up, so no pipe outlives a suspension and none
  stays down after a return.
  <!-- test: AppModelLifecycleTests.testGoingToTheBackgroundHangsUpEveryPipeAndComingBackDialsAgain -->
  <!-- test: AppModelLifecycleTests.testGoingToTheBackgroundKeepsThePartialReplyInsteadOfLosingIt -->
  <!-- test: AppModelLifecycleTests.testABackgroundThatCutsAReplyOverAPipeShortKeepsThePartial -->
  <!-- test: AppModelLifecycleTests.testComingBackDoesNotDialAPipeTheAppNeverOpened -->
  <!-- test: AppModelScenePhaseTests.testABackgroundDuringAResumeLeavesNoPipeBehind -->
  <!-- test: AppModelScenePhaseTests.testAReturnDuringAHangUpWaitsForItAndDialsAgain -->
  <!-- test: AppModelScenePhaseTests.testADialThatLandsWhileTheAppIsAwayHangsItselfUp -->
  <!-- test: AppModelScenePhaseTests.testAResumeDialsEveryPipeAtOnce -->
  <!-- test: AppModelScenePhaseTests.testABackgroundBeforeTheResumeDialsCallsThemAllOff -->
- A pairing that cannot be stored hangs up the pipe its code was spent over,
  rather than leaving one nothing in the app is holding. Every other pipe is
  reachable because it is in the session list the background pass and the
  network watcher walk — so one kept for a provider that was never added, or
  that went away while the pairing was out, never reaches that list and is the
  single pipe neither could ever close.
  <!-- test: AppModelPairingFailureTests.testAPairingWhoseKeyWillNotSaveHangsUpThePipeItWasRedeemedOver -->
  <!-- test: AppModelPairingFailureTests.testARePairingOfAProviderThatWentAwayHangsUpTheNewPipe -->
  <!-- test: AppModelPairingFailureTests.testAPairingThatStoresCleanlyKeepsItsPipe -->
- When the network under the device changes while the app is open, every
  pipe it holds is told, so its endpoint looks at the network again then,
  whether or not iroh's own watch on the routing socket noticed the move.
  A pipe already hung up is not told, and watching starts as the app
  launches rather than on its first return to the foreground.
  <!-- test: AppModelNetworkChangeTests.testAChangeToTheNetworkTellsEveryLivePipe -->
  <!-- test: AppModelNetworkChangeTests.testAPipeThatWasHungUpIsNotTold -->
  <!-- test: AppModelNetworkChangeTests.testLoadingStartsWatchingTheNetworkOnce -->
- A provider's row opens its settings, and its name and credentials are
  edited in place, keeping the id — so a machine that invites this device
  again with `gglib remote invite` keeps its conversations.
  A blank credential keeps the one stored, an edit that will not save puts
  back what it found, and a new ticket is dialled rather than saved and
  ignored.
  <!-- test: ScreenGalleryUITests.testAProviderRowOpensItsSettingsAndTheEditSticks -->
  <!-- test: AppModelProviderTests.testEditingAPipesCredentialsKeepsItsIdAndSoItsConversations -->
  <!-- test: AppModelProviderTests.testAnEmptyCredentialKeepsTheOneAlreadyStored -->
  <!-- test: AppModelProviderTests.testAnEditThatWillNotSaveLeavesTheOldCredentialsInPlace -->
  <!-- test: AppModelProviderTests.testRePairingRedeemsTheNewCodeAndDialsTheNewTicket -->
  <!-- test: AppModelProviderTests.testARefusedCodeLeavesTheProviderPairedWithTheMachineItHad -->
  <!-- test: AppModelProviderTests.testEditingAProviderThatIsGoneSaysSoRatherThanSavingNothingQuietly -->
- Removing a provider deletes its durable record before its credentials, so
  a delete that fails leaves the provider whole rather than resurrecting one
  on the next launch that can never connect.
  <!-- test: AppModelProviderTests.testAProviderWhoseRecordWillNotDeleteKeepsItsCredentials -->
  <!-- test: AppModelProviderTests.testRemovingAProviderTakesItsRecordAndItsCredentialsTogether -->
- The count of distinct tickets connected survives a relaunch, and a ticket
  connected twice counts once.
  <!-- test: DiagnosticsTests.testDistinctTicketsSurviveARelaunch -->
- A first-time user can add a provider, start a conversation, send a
  message and watch the reply stream in, driven through the real app on a
  simulator. The same walk runs against the server `GGCHAT_LIVE_BASE_URL`
  names, pasting `GGCHAT_LIVE_API_KEY` into the form; with neither set it
  falls back to a server on `127.0.0.1:8080` and skips when none is there.
  <!-- test: FirstRunUITests.testFirstRunWithTheMockProvider -->
  <!-- test: FirstRunUITests.testFirstRunAgainstAServerOnThisMachine -->
- The live walks paste their key rather than type it, and empty the
  pasteboard after. XCUITest names a typed step after its text, which put a
  key's first 18 characters in `xcodebuild`'s output and the result bundle.
  <!-- test: FirstRunUITests.testTheKeyIsPastedIntoTheFormAndLeftOffThePasteboard -->
- Which server a live walk drives is resolved from those two variables: one
  named outright is used as given and never probed, so an unreachable one
  fails rather than skipping, and an unset one falls back to the loopback
  only when something answers there.
  <!-- test: LiveServerTests.testANamedServerIsUsedAsGivenAndIsNotProbed -->
  <!-- test: LiveServerTests.testAnUnnamedServerFallsBackToTheLoopbackThatAnswers -->
  <!-- test: LiveServerTests.testNothingNamedAndNothingListeningIsASkip -->
- A credential that will not save takes the provider with it, rather than
  leaving one that fails later, and the reason names the credential.
  <!-- test: AddProviderFailureTests.testACredentialThatWillNotSaveLeavesNoHalfAddedProvider -->
  <!-- test: AddProviderFailureTests.testTheKeychainErrorSaysWhichCredentialAndWhy -->
- Saving a credential updates the Keychain item and adds one only when
  there was none to update, so the first save of a token and every save
  after it both land. Any other status is reported rather than retried as
  an add. The `SecItem` calls sit behind a seam a test can stand in for,
  because reaching the real Keychain needs a signed build carrying the
  entitlement.
  <!-- test: KeychainSecretsTests.testAnItemThatIsAlreadyThereIsUpdatedAndNeverAdded -->
  <!-- test: KeychainSecretsTests.testAnItemThatIsNotThereIsAddedOnlyAfterTheUpdateMisses -->
  <!-- test: KeychainSecretsTests.testAnUpdateThatFailsForAnyOtherReasonIsNotRetriedAsAnAdd -->
- The screens the first-run walk never reaches are visited and photographed
  too: the provider form and what it says about a bad address or ticket, a
  pipe connecting and its status pill, the providers list, and Settings
  with its count of distinct tickets and none of the readings the ADRs
  struck.
  <!-- test: ScreenGalleryUITests.testAPipeConnectsAndTheStatusPillWalks -->
  <!-- test: ScreenGalleryUITests.testTheProviderFormExplainsABadTicket -->
  <!-- test: ScreenGalleryUITests.testTheProvidersListAndTheTicketCountInSettings -->
- gglib's server status pane fills in from a real server, and is not
  offered at all by a provider that does not report one.
  <!-- test: RemainingScreensUITests.testTheServerStatusPaneAgainstARealServer -->
  <!-- test: RemainingScreensUITests.testTheStatusPaneIsHiddenForAServerThatDoesNotReport -->
- A closed pipe turns its status pill into a reconnect, and pressing it
  brings the pipe back. The pill is a way back in every state but one — a
  dial already in flight — so a status that has gone stale is still
  something you can press.
  <!-- test: RemainingScreensUITests.testAClosedPipeOffersAReconnect -->
  <!-- test: AppModelDialTests.testOnlyADialInFlightWithholdsTheWayBack -->
- Text grows at the largest accessibility size, and the test measures it,
  so a launch argument that silently changes nothing cannot pass for a
  Dynamic Type check.
  <!-- test: RemainingScreensUITests.testTheAppAtAnAccessibilityTypeSize -->
- Reopening the app returns you to the conversation you left.
  <!-- test: SwiftDataStoreTests.testAppModelKeepsSelectionAndPersistsThroughTheStore -->
- A block quote's `>` marker and a list item's indentation stay out of the
  rendered text.
  <!-- test: MarkdownTests.testListsHeadingsQuotesAndRules -->
- A line break inside a paragraph reads as a space, so the words either
  side of it never run together: in a heading, a list item or a quote too,
  and beside code, emphasis or a link. A hard break, two spaces or a
  backslash at the end of the line, starts a new line.
  <!-- test: MarkdownTests.testASoftBreakReadsAsASpace -->
  <!-- test: MarkdownTests.testASoftBreakBesideCodeEmphasisAndALinkReadsAsASpace -->
  <!-- test: MarkdownTests.testAHardBreakIsANewline -->
- Punctuation in the transcript reads as typed: `---` stays three hyphens
  rather than becoming an em dash, and straight quotes stay straight.
  <!-- test: MarkdownTests.testPunctuationReadsAsTyped -->
- The rules that decide when a change to a chat branches it are gglib's,
  held to every case gglib records: an edit of an answered question, a
  regenerate, an edit of a reply and a branch from a turn each copy the chat
  into a new one of its family, and only an edit of the last question
  nothing answers is made in place; a change that names no message, changes
  nothing, regenerates a question or gives a reply an image is refused with
  gglib's code. The options a family holds where its chats part are the ones
  gglib finds, each shown by its first line of text, cut at 80 characters,
  or by what stands in for an image (ADR 0010).
  <!-- test: BranchingContractTests.testEveryChangeIsPlannedOrRefusedAsGglibDoes -->
  <!-- test: BranchingContractTests.testEveryFamilysBranchPointsAreTheOnesGglibFinds -->
  <!-- test: BranchRulesTests.testAQuestionIsShownByItsFirstLineCutAtEightyCharacters -->
  <!-- test: BranchRulesTests.testAQuestionOfImagesAloneSaysHowMany -->
  <!-- test: BranchRulesTests.testAReplyIsShownByItsLastLineOfText -->
  <!-- test: BranchRulesTests.testAFamilyOfThisDevicesChatsPartsWhereItsTurnsDiffer -->
  <!-- test: BranchRulesTests.testAnEditOfTheLastQuestionIsMadeInPlaceOnlyWhileNothingIsWritingItsReply -->
  <!-- test: BranchRulesTests.testAReplyEditedToItsOwnTextIsRefused -->
  <!-- test: BranchRulesTests.testATieInTimeIsBrokenByTheHigherChatID -->
- A saved reply is never rewritten on this device. Editing a question that
  has been answered, or regenerating a reply, opens a new branch of the
  conversation, a copy as far as the change with the same title, model,
  system prompt and Thinking choice, and answers it there; the conversation
  it was made on is left as it was, and each offers the other's reply where
  they part. An edited reply is kept as written on a branch and not
  answered; Branch from here copies the conversation and sends nothing. Only
  the last question nothing answers, while no reply to it is being written,
  is edited in place, and a reply saved as it was changes nothing. A branch
  made while the reply it parts from streams is answered at once. A copy carries no
  run, a branch of a branch belongs to the first conversation's family, and
  a branch's lineage survives a relaunch (ADR 0010).
  <!-- test: AppModelBranchingTests.testAnEditOfAnAnsweredQuestionOpensABranchAnsweredThere -->
  <!-- test: AppModelBranchingTests.testARegenerateBranchesAndBothConversationsOfferEitherReply -->
  <!-- test: AppModelBranchingTests.testAnEditedReplyIsKeptAsWrittenOnABranchAndNotAnswered -->
  <!-- test: AppModelBranchingTests.testBranchFromHereCopiesTheConversationAndSendsNothing -->
  <!-- test: AppModelBranchingTests.testAnEditOfTheLastQuestionNothingAnswersIsMadeInPlace -->
  <!-- test: AppModelBranchingTests.testARegenerateOfAQuestionIsRefusedAndChangesNothing -->
  <!-- test: AppModelBranchingTests.testAReplySavedAsItWasIsRefusedAndMakesNoBranch -->
  <!-- test: AppModelBranchingTests.testAQuestionWhoseReplyIsStreamingIsEditedOnABranch -->
  <!-- test: ConversationBranchesTests.testABranchCopiesTheSettingsAndNoRun -->
  <!-- test: ConversationBranchesTests.testABranchOfABranchIsOfTheFirstFamilyAndCopiesTheFirstMessages -->
  <!-- test: ConversationBranchesTests.testAQuestionEditedInPlaceIsANewMessage -->
  <!-- test: BranchStoreTests.testABranchsLineageSurvivesTheRoundTrip -->
- Any message of a conversation on this device can be edited from its
  menu, a question asked again by Send and a reply kept as written by Save,
  and a reply regenerated or a turn branched from. The editor saves only a
  change. Where the conversation's
  family parts, the turn says which branch is open, of how many, and its
  previous and next open the others; the list names each option by its line.
  An edited reply opens its branch with the switcher, and Previous goes back
  to the conversation as it was (ADR 0010).
  <!-- test: BranchingUITests.testAnEditedReplyOpensABranchAndPreviousGoesBack -->
  <!-- test: BranchSwitcherTests.testTheSwitcherSaysWhichOfHowManyTheOpenConversationIs -->
  <!-- test: BranchSwitcherTests.testAnOptionIsListedByItsLineOrWhatStandsInForOne -->
  <!-- test: MessageChangesTests.testEachMenuItemMakesItsOwnChange -->
  <!-- test: MessageChangesTests.testTheEditorSavesOnlyAChange -->
- A Mac's chat offers the same changes from each turn's menu, and the Mac
  makes them by the same rules, keeping any branch as one of its chats: the
  change names the Mac's row, the chat the Mac names opens with its branch
  points, a reply's at its text even when it first called a tool, and a
  question the Mac says to answer is answered by a turn that says so, with
  the Thinking choice set here. A refusal says the rule's sentence, and a
  chat that ends in a question nothing answers offers Answer. Nothing is
  sent while a reply is written or another change is on its way, or to a
  Mac out of reach; a change answered after its chat was left opens
  nothing; an editor open while the chat is read again still names its
  row; and nothing of either chat is written here. The wire shapes replay
  the bodies gglib records, and its refusals keep their codes (ADR 0010).
  <!-- test: HubChatBranchingTests.testAnEditOfAnAnsweredQuestionOpensTheMacsBranchAndAnswersIt -->
  <!-- test: HubChatBranchingTests.testBranchFromHereOpensTheBranchAndAnswersNothing -->
  <!-- test: HubChatBranchingTests.testARefusalSaysTheRulesSentence -->
  <!-- test: HubChatBranchingTests.testAnswerAnswersTheQuestionNothingAnswers -->
  <!-- test: HubChatBranchingTests.testTheAnswerSaysTheThinkingChoiceOfTheChatItWasAskedFrom -->
  <!-- test: HubChatBranchingTests.testAPointAtAReplyThatCalledAToolIsDrawnAtItsText -->
  <!-- test: HubChatBranchingTests.testOnlyASentQuestionIsDrawnAboveItsReply -->
  <!-- test: HubChatBranchGuardsTests.testAChangeWhileAReplyIsWrittenOrAChangeIsOnItsWayIsRefused -->
  <!-- test: HubChatBranchGuardsTests.testAChangeToAMacOutOfReachIsRefused -->
  <!-- test: HubChatBranchGuardsTests.testAChangeAnsweredAfterItsChatWasLeftOpensNothing -->
  <!-- test: HubChatBranchGuardsTests.testAChangeMadeInPlaceReadsTheChatAgainAndAnswersIt -->
  <!-- test: HubChatBranchGuardsTests.testAnEditorOpenAcrossAReadStillNamesItsRow -->
  <!-- test: HubChatBranchesWireTests.testABranchOpensWithItsPointAndAnswerable -->
  <!-- test: HubChatBranchesWireTests.testAChatWithoutBranchesSaysNeither -->
  <!-- test: HubChatBranchesWireTests.testAChangeIsTheRecordedBody -->
  <!-- test: HubChatBranchesWireTests.testTheAnswerTurnIsTheRecordedBody -->
  <!-- test: HubChatBranchesWireTests.testEachRowIsKeyedByTheRowThatStartsItsTurn -->
  <!-- test: HubChatBranchesWireTests.testGglibsRefusalsOfAChangeKeepTheirCodes -->

