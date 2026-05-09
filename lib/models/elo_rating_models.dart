enum EloPool {
  scoreboard,
  countNine,
}

class EloRatingRecord {
  const EloRatingRecord({
    required this.playerId,
    required this.rating,
    required this.ratedGames,
    required this.wins,
    required this.losses,
    required this.updatedAtMs,
  });

  final String playerId;
  final int rating;
  final int ratedGames;
  final int wins;
  final int losses;
  final int updatedAtMs;

  Map<String, dynamic> toJson() => {
        'playerId': playerId,
        'rating': rating,
        'ratedGames': ratedGames,
        'wins': wins,
        'losses': losses,
        'updatedAtMs': updatedAtMs,
      };

  static EloRatingRecord fromJson(Map<String, dynamic> j) {
    return EloRatingRecord(
      playerId: j['playerId'] as String? ?? '',
      rating: (j['rating'] as num?)?.toInt() ?? 1500,
      ratedGames: (j['ratedGames'] as num?)?.toInt() ?? 0,
      wins: (j['wins'] as num?)?.toInt() ?? 0,
      losses: (j['losses'] as num?)?.toInt() ?? 0,
      updatedAtMs: (j['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

class EloMatchUpdate {
  const EloMatchUpdate({
    required this.winnerBefore,
    required this.winnerAfter,
    required this.loserBefore,
    required this.loserAfter,
    required this.kWinner,
    required this.kLoser,
    required this.expectedWinner,
    required this.expectedLoser,
  });

  final int winnerBefore;
  final int winnerAfter;
  final int loserBefore;
  final int loserAfter;
  final int kWinner;
  final int kLoser;
  final double expectedWinner;
  final double expectedLoser;
}
