ALTER TABLE public.laundry_wash_batches ADD COLUMN cart_number bigint;
WITH numbered AS (SELECT id,row_number() OVER (ORDER BY created_at,id) AS n FROM public.laundry_wash_batches)
UPDATE public.laundry_wash_batches b SET cart_number=n.n FROM numbered n WHERE b.id=n.id;
ALTER TABLE public.laundry_wash_batches ALTER COLUMN cart_number SET NOT NULL;
ALTER TABLE public.laundry_wash_batches ALTER COLUMN cart_number ADD GENERATED ALWAYS AS IDENTITY;
ALTER TABLE public.laundry_wash_batches ADD CONSTRAINT laundry_wash_batches_cart_number_key UNIQUE(cart_number);
DO $migration$ DECLARE next_number bigint; BEGIN
SELECT coalesce(max(cart_number),0)+1 INTO next_number FROM public.laundry_wash_batches;
EXECUTE format('ALTER TABLE public.laundry_wash_batches ALTER COLUMN cart_number RESTART WITH %s',next_number);
END $migration$;
