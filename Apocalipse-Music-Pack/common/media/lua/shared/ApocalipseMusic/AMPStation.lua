require "ApocalipseBRRadio/ABRRadioMusic"

-- This file owns station identity and in-between talk. Song modules only
-- register catalog entries. The framework arbitrates music and text broadcasts.
ABRRadio.registerMusicStation({
    id = "amp_music",
    name = { EN = "Apocalipse Music", PTBR = "Musica Apocalipse" },
    frequency = 94200,
    category = "Radio",
    color = { r = 0.8, g = 0.65, b = 0.25 },
    signalStrength = -1,
    talkChance = 35, -- percent, at most one talk segment between songs
})

ABRRadio.registerMusicTalk({
    id = "amp_ident", station = "amp_music", duration = 8, weight = 10,
    lines = {
        { at = 0, text = { EN = "You are listening to Apocalipse Music, 94.2 FM.", PTBR = "Voce esta ouvindo Musica Apocalipse, 94.2 FM." } },
        { at = 4, text = { EN = "Another song for everyone still out there.", PTBR = "Mais uma musica para quem ainda esta por ai." } },
    },
})
ABRRadio.registerMusicTalk({
    id = "amp_survivors", station = "amp_music", duration = 9, weight = 8,
    lines = {
        { at = 0, text = { EN = "Keep your water clean and your radio close.", PTBR = "Mantenha sua agua limpa e seu radio por perto." } },
        { at = 5, text = { EN = "This next one goes out to the survivors.", PTBR = "A proxima vai para os sobreviventes." } },
    },
})
ABRRadio.registerMusicTalk({
    id = "amp_night", station = "amp_music", duration = 7, weight = 6,
    lines = {
        { at = 0, text = { EN = "Somewhere, someone else is listening too.", PTBR = "Em algum lugar, alguem tambem esta ouvindo." } },
        { at = 4, text = { EN = "Let the music keep you company.", PTBR = "Deixe a musica te fazer companhia." } },
    },
})
