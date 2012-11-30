package com.sajarvis.scrawl;

import android.content.Intent;
import android.os.Bundle;
import android.preference.PreferenceManager;
import android.support.v4.app.Fragment;
import android.support.v4.app.FragmentActivity;
import android.util.Log;
import android.view.Menu;
import android.view.MenuInflater;
import android.view.MenuItem;

import com.sajarvis.scrawl.preferences.SettingsActivity;

/**
 * An activity representing a single screen.
 * <p>
 * This activity is mostly just a 'shell' activity containing nothing more than
 * a {@link Fragment}.
 */
public class ScreenDetailActivity extends FragmentActivity {

	private final String TAG = "scrawl";
	
	@Override
	protected void onCreate(Bundle savedInstanceState) {
		super.onCreate(savedInstanceState);
		Log.v(TAG, "Creating screen activity.");
		setContentView(R.layout.activity_screen_detail);
		
		// Set default preferences. Will only happen first launch.
		PreferenceManager.setDefaultValues(this, R.xml.preferences, false);
		
		// savedInstanceState is non-null when there is fragment state
		// saved from previous configurations of this activity
		// (e.g. when rotating the screen from portrait to landscape).
		// In this case, the fragment will automatically be re-added
		// to its container so we don't need to manually add it.
		if (savedInstanceState == null) {
			// Create the detail fragment and add it to the activity
			// using a fragment transaction.
			Bundle arguments = new Bundle();
			arguments.putString(ScreenDetailFragment.ARG_ITEM_ID, getIntent()
					.getStringExtra(ScreenDetailFragment.ARG_ITEM_ID));
			ScreenDetailFragment fragment = new ScreenDetailFragment();
			fragment.setArguments(arguments);
			getSupportFragmentManager().beginTransaction()
					.add(R.id.screen_detail_container, fragment).commit();
		}
	}

	@Override
	public boolean onCreateOptionsMenu(Menu menu) {
		MenuInflater inflater = getMenuInflater();
	    inflater.inflate(R.menu.options, menu);
	    return true;
	}
	
	@Override
	public boolean onOptionsItemSelected(MenuItem item) {
		switch (item.getItemId()) {
		case R.id.settings:
			Log.v(TAG, "Loading the settings menu.");
			startActivity(new Intent(this, SettingsActivity.class));
			return true;
		}
		return super.onOptionsItemSelected(item);
	}
}