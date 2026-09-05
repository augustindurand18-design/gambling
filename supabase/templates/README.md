# Gabarits d'e-mail

Trois gabarits identiques — `confirmation`, `magic_link`, `recovery` — parce que
GoTrue choisit l'un ou l'autre selon l'état du compte, sans que l'utilisateur
n'en sache rien : une première demande est une inscription, les suivantes sont
journalisées comme des « récupérations ». Lui envoyer trois messages différents
pour la même action n'aurait pas de sens.

Chacun envoie un code à six chiffres, jamais un lien. Un lien exigerait des
liens profonds, donc un domaine associé, donc le compte Apple Developer ; le
code se recopie depuis n'importe quel simulateur.

## Aucun commentaire dans ces fichiers

Go substitue les variables de gabarit dans **tout** le fichier, commentaires
HTML compris. Une version precedente expliquait en commentaire que le gabarit
par defaut envoyait un lien, en citant `{{ .ConfirmationURL }}` — la variable
etait donc remplacee par une vraie URL `http://127.0.0.1:54321/auth/v1/verify`
avec un jeton, cachee dans chaque message envoye.

Gmail supprimait ces e-mails sans avertissement : une adresse locale porteuse
d'un jeton est une signature de hameconnage. Les envois etaient acceptes par
Resend, ne revenaient jamais en erreur, et n'arrivaient nulle part.

Toute explication va donc ici, jamais dans les gabarits.

## Projet distant

Ces fichiers ne servent qu'en local. Pour le projet Supabase distant, les
memes gabarits doivent etre poses dans le tableau de bord : `config.toml`
n'est pas lu par le projet en ligne.
