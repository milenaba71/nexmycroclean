package com.mycroclean.rfid;

import android.app.*;
import android.os.Bundle;
import android.os.Handler;
import android.bluetooth.*;
import android.webkit.*;
import android.net.Uri;
import java.io.*;
import java.util.*;
import org.json.JSONArray;
import org.json.JSONObject;

public class ReaderApp extends Activity {
    private static final String HOME = "https://gestionale.mycroclean.com";
    private static final UUID RFID = UUID.fromString("2ad8a392-0e49-e52c-a6d2-60834c012263");
    private WebView web;
    private volatile BluetoothSocket active;
    private final Handler handler = new Handler();
    private int generation;
    private static boolean trusted(Uri uri) {
        return "https".equals(uri.getScheme()) && "gestionale.mycroclean.com".equals(uri.getHost())
            && (uri.getPort() == -1 || uri.getPort() == 443);
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        web = new WebView(this);
        setContentView(web);
        web.getSettings().setJavaScriptEnabled(true);
        web.getSettings().setDomStorageEnabled(true);
        web.getSettings().setAllowFileAccess(false);
        web.getSettings().setAllowContentAccess(false);
        web.getSettings().setUserAgentString(web.getSettings().getUserAgentString()+" MycrocleanRFID/1");
        web.setWebViewClient(new WebViewClient() {
            @Override public void onPageFinished(WebView view,String url) {
                if (!trusted(Uri.parse(url))) return;
                try (BufferedReader reader=new BufferedReader(new InputStreamReader(getAssets().open("bulk.js"),"UTF-8"))) {
                    StringBuilder script=new StringBuilder();
                    String line;
                    while((line=reader.readLine())!=null) script.append(line).append('\n');
                    view.evaluateJavascript(script.toString(),null);
                } catch(IOException e){new AlertDialog.Builder(ReaderApp.this).setMessage("Modulo RFID indisponibile").setPositiveButton("Chiudi",null).show();}
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest req) {
                Uri uri = req.getUrl();
                if ("mycro-rfid".equals(uri.getScheme())) {
                    if (req.isForMainFrame() && req.hasGesture() && trusted(Uri.parse(view.getUrl())) && "scan".equals(uri.getHost())) {
                        try {
                            int count = Integer.parseInt(uri.getQueryParameter("count"));
                            String token = uri.getQueryParameter("token");
                            if (count > 0 && count <= 1000 && token != null && token.matches("[a-zA-Z0-9-]{1,80}"))
                                choose(count, token);
                        } catch (NumberFormatException ignored) {}
                    }
                    return true;
                }
                return req.isForMainFrame() && !trusted(uri);
            }
        });
        web.loadUrl(HOME);
    }
    private void choose(int count, String token) {
        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        List<BluetoothDevice> readers = new ArrayList<>();
        if (adapter != null && adapter.isEnabled())
            for (BluetoothDevice d : adapter.getBondedDevices())
                if (d.getName() != null && d.getName().toUpperCase(Locale.ROOT).startsWith("RFD8500")) readers.add(d);
        if (readers.isEmpty()) {
            new AlertDialog.Builder(this).setMessage("Accendi il Bluetooth e associa la RFD8500 al palmare.").setPositiveButton("Chiudi",null).show();
        } else if (readers.size() == 1) scan(readers.get(0),count,token);
        else {
            String[] names = new String[readers.size()];
            for (int i=0;i<names.length;i++) names[i]=readers.get(i).getName();
            new AlertDialog.Builder(this).setTitle("Scegli la pistola").setItems(names,(d,i)->scan(readers.get(i),count,token)).show();
        }
    }
    private void closeSocket() {
        BluetoothSocket socket = active;
        active = null;
        if (socket != null) try { socket.close(); } catch(IOException ignored) {}
    }
    private static void send(BluetoothSocket socket,String command) throws IOException {
        OutputStream out = socket.getOutputStream();
        out.write((command+"\r\n").getBytes("US-ASCII"));
        out.flush();
    }
    private void scan(BluetoothDevice reader, int count, String token) {
        closeSocket();
        final int session = ++generation;
        final Set<String> tags = Collections.synchronizedSet(new LinkedHashSet<String>());
        final BluetoothSocket socket;
        try { socket=reader.createRfcommSocketToServiceRecord(RFID); active=socket; }
        catch(IOException e){new AlertDialog.Builder(this).setMessage(e.toString()).setPositiveButton("Chiudi",null).show();return;}
        AlertDialog progress = new AlertDialog.Builder(this).setTitle("Lettura RFID").setMessage("Collegamento alla pistola…")
            .setPositiveButton("Ferma e mantieni",null).setNegativeButton("Annulla",null).setCancelable(false).show();
        class Stop {
            boolean requested, discard, inventory;
            final Runnable deadline=()->{try{socket.close();}catch(IOException ignored){}};
            synchronized void begin() throws IOException {
                if(requested)return;
                send(socket,"inventory"); inventory=true;
            }
            synchronized void request(boolean cancel) {
                if(requested)return;
                requested=true; discard=cancel;
                runOnUiThread(()->{
                    if(session!=generation || !progress.isShowing())return;
                    progress.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(false);
                    progress.getButton(AlertDialog.BUTTON_NEGATIVE).setEnabled(false);
                    progress.setMessage("Arresto della pistola… · "+tags.size()+" tag");
                });
                if(!inventory){new Thread(deadline).start();return;}
                handler.postDelayed(deadline,5000);
                new Thread(()->{
                    try {send(socket,"abort");} catch(IOException e){deadline.run();}
                }).start();
            }
        }
        final Stop stop=new Stop();
        progress.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(false);
        progress.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v->stop.request(false));
        progress.getButton(AlertDialog.BUTTON_NEGATIVE).setOnClickListener(v->stop.request(true));
        Runnable timeout=()->stop.request(false);
        handler.postDelayed(timeout,15000);
        new Thread(()->{
            String error=null;
            try {
                socket.connect();
                send(socket,"connect");
                BufferedReader input=new BufferedReader(new InputStreamReader(socket.getInputStream(),"US-ASCII"));
                String line;
                while(true) {
                    line=input.readLine();
                    if(line==null)throw new IOException("Connessione terminata.");
                    synchronized(stop) {
                        if(stop.requested){
                            if(line.replace(" ","").startsWith("Command:abort,Status:OK"))break;
                            continue;
                        }
                        if(line.contains("Status:") && !line.contains("Status:OK") && !line.contains("Connection Successful"))
                            throw new IOException(line);
                        if(!stop.inventory && line.contains("Connection Successful")) {
                            stop.begin();
                            handler.removeCallbacks(timeout); handler.postDelayed(timeout,120000);
                            runOnUiThread(()->{synchronized(stop){if(!stop.requested && session==generation)progress.setMessage("Avvicina i capi · 0 / "+count);}});
                        } else if(stop.inventory && line.startsWith(",,")) {
                            String[] fields=line.split(",",-1);
                            if(fields.length<3)continue;
                            String epc=fields[2].trim().toUpperCase(Locale.ROOT);
                            if(!epc.matches("(?:[0-9A-F]{2}){1,62}") || !tags.add(epc))continue;
                            int n=tags.size();
                            if(n==count){stop.request(false);continue;}
                            runOnUiThread(()->{synchronized(stop){if(!stop.requested && session==generation){progress.setMessage(n+" / "+count+" tag distinti");progress.getButton(AlertDialog.BUTTON_POSITIVE).setEnabled(true);}}});
                        }
                    }
                }
            } catch(Exception e){error=e.toString();}
            finally {
                handler.removeCallbacks(timeout);handler.removeCallbacks(stop.deadline);
                if(stop.inventory && !stop.requested)try{send(socket,"abort");}catch(IOException ignored){}
                try {socket.close();}catch(IOException ignored){}
            }
            final String message=error;
            runOnUiThread(()->{
                if(session!=generation || isFinishing())return;
                active=null; progress.dismiss();
                if(stop.discard)return;
                if(message!=null){
                    AlertDialog.Builder interrupted=new AlertDialog.Builder(this).setTitle("Lettura interrotta").setMessage(tags.size()+" / "+count+" tag. La pistola non ha confermato l’arresto. "+message);
                    if(!tags.isEmpty())interrupted.setPositiveButton("Mantieni letture",(d,i)->deliver(token,tags));
                    interrupted.setNegativeButton("Chiudi",null).show();
                } else deliver(token,tags);
            });
        }).start();
    }
    private void deliver(String token,Set<String> tags) {
        if(web.getUrl()==null || !trusted(Uri.parse(web.getUrl())))return;
        final JSONArray result;
        synchronized(tags){result=new JSONArray(tags);}
        web.evaluateJavascript("window.dispatchEvent(new CustomEvent('mycro-rfid-result',{detail:{token:"+JSONObject.quote(token)+",tags:"+result+"}}))",null);
    }
    @Override public void onBackPressed(){if(web.canGoBack())web.goBack();else super.onBackPressed();}
    @Override public void onDestroy(){generation++;closeSocket();handler.removeCallbacksAndMessages(null);super.onDestroy();}
}
