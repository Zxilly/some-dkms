#include <linux/module.h>
#include <net/tcp.h>
#include <linux/inet.h>

static int rate = 100000000;
module_param(rate, int, 0644);
static int feedback = 2;
module_param(feedback, int, 0644);

struct sample {
	u32	_acked;
	u32	_losses;
	u32	_tstamp_us;
};

struct alg {
	u64	rate;
	u16	start;
	u16	end;
	u32	curr_acked;
	u32	curr_losses;
	struct sample *samples;
};

static void alg_main(struct sock *sk, const struct rate_sample *rs)
{
	struct tcp_sock *tp = tcp_sk(sk);
	struct alg *alg = inet_csk_ca(sk);
	u32 now = tp->tcp_mstamp;
	u32 cwnd;
	u16 start, end;
	u64 prate;

	if (rs->delivered < 0 || rs->interval_us <= 0)
		return;

	cwnd = alg->rate;
	if (!alg->samples) {
		cwnd /= tp->mss_cache;
		cwnd *= (tp->srtt_us >> 3);
		cwnd /= USEC_PER_SEC;
		tp->snd_cwnd = min(2 * cwnd, tp->snd_cwnd_clamp);
		sk->sk_pacing_rate = min_t(u64, alg->rate, READ_ONCE(sk->sk_max_pacing_rate));
		return;
	}
	
	alg->curr_acked += rs->acked_sacked;
	alg->curr_losses += rs->losses;
	end = alg->end ++;
	alg->samples[end]._acked = rs->acked_sacked;
	alg->samples[end]._losses = rs->losses;
	alg->samples[end]._tstamp_us = now;

	start = alg->start;
	while ((__s16)(start - end) < 0) {
		if (2 * (now -  alg->samples[start]._tstamp_us) > feedback * tp->srtt_us) {
			alg->curr_acked -= alg->samples[start]._acked;
			alg->curr_losses -= alg->samples[start]._losses;
			alg->start ++;
		}
		start ++;
	}
	cwnd /= tp->mss_cache;
	cwnd *= alg->curr_acked + alg->curr_losses;
	cwnd /= alg->curr_acked;
	cwnd *= (tp->srtt_us >> 3);
	cwnd /= USEC_PER_SEC;

	prate = (alg->curr_acked + alg->curr_losses) << 10;
	prate /= alg->curr_acked;
	prate *= alg->rate;
	prate = prate >> 10;

	// printk("##### curr_ack:%llu curr_loss:%llu rsloss:%llu satrt:%llu  end:%llu cwnd:%llu rate:%llu prate:%llu\n",
	// 		alg->curr_acked,
	// 		alg->curr_losses,
	// 		rs->losses,
	// 		alg->start,
	// 		alg->end,
	// 		cwnd,
	// 		rate,
	// 		prate);
	tp->snd_cwnd = min(cwnd, tp->snd_cwnd_clamp);
	sk->sk_pacing_rate = min_t(u64, prate, sk->sk_max_pacing_rate);
}

static void alg_init(struct sock *sk)
{
	struct alg *alg = inet_csk_ca(sk);

	alg->rate = (u64)rate;
	alg->start = 0;
	alg->end = 0;
	alg->curr_acked = 0;
	alg->curr_losses = 0;
	alg->samples = kmalloc(U16_MAX * sizeof(struct sample), GFP_ATOMIC); // ATOMIC ??
	cmpxchg(&sk->sk_pacing_status, SK_PACING_NONE, SK_PACING_NEEDED);
}

static void alg_release(struct sock *sk)
{
	struct alg *alg = inet_csk_ca(sk);

	if (alg->samples)
		kfree(alg->samples);
}

static u32 alg_ssthresh(struct sock *sk)
{
	return TCP_INFINITE_SSTHRESH;
}

static u32 alg_undo_cwnd(struct sock *sk)
{
	struct tcp_sock *tp = tcp_sk(sk);
	return tp->snd_cwnd;
}

static struct tcp_congestion_ops tcp_alg_cong_ops __read_mostly = {
	.flags		= TCP_CONG_NON_RESTRICTED,
	.name		= "alg",
	.owner		= THIS_MODULE,
	.init		= alg_init,
	.release	= alg_release,
	.cong_control	= alg_main,
	.ssthresh	= alg_ssthresh,
	.undo_cwnd 	= alg_undo_cwnd,
};

static int __init alg_register(void)
{
	BUILD_BUG_ON(sizeof(struct alg) > ICSK_CA_PRIV_SIZE);
	return tcp_register_congestion_control(&tcp_alg_cong_ops);
}

static void __exit alg_unregister(void)
{
	tcp_unregister_congestion_control(&tcp_alg_cong_ops);
}

module_init(alg_register);
module_exit(alg_unregister);
MODULE_LICENSE("GPL");